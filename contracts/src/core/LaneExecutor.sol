// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {CCIPReceiver} from "@chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ICcipRouter} from "../interfaces/ICcipRouter.sol";
import {ILaneExecutor} from "../interfaces/ILaneExecutor.sol";
import {ILaneController} from "../interfaces/ILaneController.sol";
import {IPausable} from "../interfaces/IPausable.sol";
import {IReceiver} from "../interfaces/IReceiver.sol";
import {CreReportAuth} from "../libraries/CreReportAuth.sol";

/// @title LaneExecutor
/// @notice Per-chain CCIP endpoint for parimutuel races: sends race legs to the next
///         chain in a lane circuit and relays received hops to the canonical
///         LaneController on the home (betting) chain.
contract LaneExecutor is CCIPReceiver, Ownable, Pausable, ILaneExecutor, IReceiver, ReentrancyGuard {
    ILaneController private s_laneController;
    ICcipRouter public immutable s_ccipRouter;
    address public creForwarder;

    /// @notice CCIP chain selector for this deployment.
    uint64 public localChainSelector;
    /// @notice CCIP chain selector where bets and settlement are authoritative.
    uint64 public homeChainSelector;
    /// @notice LaneController on the home chain (where users bet).
    address public canonicalController;
    /// @notice LaneExecutor on the home chain — relay target for spoke-chain hop receipts.
    address public homeExecutor;

    mapping(uint64 => address) public remoteExecutors;
    mapping(address => bool) public hopSenders;

    event HopSent(
        bytes32 indexed messageId, uint256 indexed roundId, uint8 indexed laneId, uint64 destChainSelector
    );
    event HopReceived(uint256 indexed roundId, uint8 indexed laneId, uint64 sourceChainSelector, uint256 latency);
    event HopRelayed(bytes32 indexed messageId, uint256 indexed roundId, uint8 indexed laneId);

    error ControllerNotSet();
    error UnknownDestination(uint64 destChainSelector);
    error UnknownSource(uint64 sourceChainSelector);
    error UnauthorizedSource(address sender, address expected);
    error NotAuthorized();
    error ReportExecutionFailed();
    error ZeroAddress();
    error HomeConfigNotSet();
    error InvalidSendTime();
    error ControllerMismatch();
    error HomeControllerPaused();
    error InsufficientCcipFee(uint256 required, uint256 available);

    uint256 public constant MAX_CLOCK_SKEW = 15 minutes;

    modifier onlyHopSender() {
        if (msg.sender != owner() && !hopSenders[msg.sender] && msg.sender != creForwarder) {
            revert NotAuthorized();
        }
        _;
    }

    constructor(address router, address initialOwner) CCIPReceiver(router) Ownable(initialOwner) {
        s_ccipRouter = ICcipRouter(router);
    }

    receive() external payable {}

    function laneController() external view returns (address) {
        return address(s_laneController);
    }

    function setLaneController(address controller) external onlyOwner {
        if (controller == address(0)) revert ZeroAddress();
        if (canonicalController != address(0) && controller != canonicalController) revert ControllerMismatch();
        s_laneController = ILaneController(controller);
    }

    /// @notice Wires canonical home-chain routing for multi-chain parimutuel races.
    function setHomeConfig(
        uint64 _localChainSelector,
        uint64 _homeChainSelector,
        address _canonicalController,
        address _homeExecutor
    ) external onlyOwner {
        if (_canonicalController == address(0) || _homeExecutor == address(0)) revert ZeroAddress();
        localChainSelector = _localChainSelector;
        homeChainSelector = _homeChainSelector;
        canonicalController = _canonicalController;
        homeExecutor = _homeExecutor;
        if (_localChainSelector == _homeChainSelector) {
            s_laneController = ILaneController(_canonicalController);
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setRemoteExecutor(uint64 chainSelector, address executor) external onlyOwner {
        remoteExecutors[chainSelector] = executor;
    }

    function setHopSender(address sender, bool allowed) external onlyOwner {
        hopSenders[sender] = allowed;
    }

    function setCreForwarder(address forwarder) external onlyOwner {
        if (forwarder == address(0)) revert ZeroAddress();
        creForwarder = forwarder;
    }

    /// @inheritdoc IReceiver
    function onReport(bytes calldata, bytes calldata report) external nonReentrant {
        if (msg.sender != creForwarder) revert NotAuthorized();
        CreReportAuth.assertExecutorReport(report);
        (bool ok,) = address(this).call(report);
        if (!ok) revert ReportExecutionFailed();
    }

    function sendHop(uint256 roundId, uint8 laneId, uint64 destChainSelector)
        external
        onlyHopSender
        whenNotPaused
        returns (bytes32 messageId)
    {
        address destExecutor = remoteExecutors[destChainSelector];
        if (destExecutor == address(0)) revert UnknownDestination(destChainSelector);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destExecutor),
            data: abi.encode(roundId, laneId, destChainSelector, block.timestamp),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: address(0)
        });

        messageId = _ccipSend(destChainSelector, message);
        emit HopSent(messageId, roundId, laneId, destChainSelector);
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override whenNotPaused {
        if (canonicalController == address(0)) revert HomeConfigNotSet();

        address expectedSender = remoteExecutors[message.sourceChainSelector];
        if (expectedSender == address(0)) revert UnknownSource(message.sourceChainSelector);

        address sender = abi.decode(message.sender, (address));
        if (sender != expectedSender) revert UnauthorizedSource(sender, expectedSender);

        (uint256 roundId, uint8 laneId, uint64 hopChainSelector, uint256 sendTime) =
            abi.decode(message.data, (uint256, uint8, uint64, uint256));
        if (sendTime > block.timestamp + MAX_CLOCK_SKEW) revert InvalidSendTime();

        uint256 latency = sendTime > block.timestamp ? 0 : block.timestamp - sendTime;
        emit HopReceived(roundId, laneId, message.sourceChainSelector, latency);

        if (localChainSelector == homeChainSelector) {
            if (IPausable(canonicalController).paused()) revert HomeControllerPaused();
            uint256 recorded = sendTime > block.timestamp ? block.timestamp : sendTime;
            ILaneController(canonicalController).recordHop(roundId, laneId, hopChainSelector, recorded);
        } else {
            _relayHopToHome(roundId, laneId, hopChainSelector, sendTime);
        }
    }

    function _relayHopToHome(uint256 roundId, uint8 laneId, uint64 hopChainSelector, uint256 sendTime) internal {
        if (homeExecutor == address(0)) revert HomeConfigNotSet();

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(homeExecutor),
            data: abi.encode(roundId, laneId, hopChainSelector, sendTime),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: address(0)
        });

        bytes32 messageId = _ccipSend(homeChainSelector, message);
        emit HopRelayed(messageId, roundId, laneId);
    }

    function _ccipSend(uint64 destChainSelector, Client.EVM2AnyMessage memory message)
        internal
        returns (bytes32 messageId)
    {
        uint256 fee = s_ccipRouter.getFee(destChainSelector, message);
        if (address(this).balance < fee) revert InsufficientCcipFee(fee, address(this).balance);
        messageId = s_ccipRouter.ccipSend{value: fee}(destChainSelector, message);
    }
}
