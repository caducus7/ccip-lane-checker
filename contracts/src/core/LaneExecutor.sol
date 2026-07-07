// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {CCIPReceiver} from "@chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ICcipRouter} from "../interfaces/ICcipRouter.sol";
import {ILaneExecutor} from "../interfaces/ILaneExecutor.sol";
import {ILaneController} from "../interfaces/ILaneController.sol";
import {IReceiver} from "../interfaces/IReceiver.sol";
import {CreReportAuth} from "../libraries/CreReportAuth.sol";

/// @title LaneExecutor
/// @notice Per-chain CCIP endpoint for parimutuel races: sends race legs to the next
///         chain in a lane circuit and records received hops on the LaneController.
/// @dev Hop sends are driven externally (owner, authorized hopSenders, or CRE forwarder
///      via `onReport`) so gas limits stay flat instead of nesting sends inside receives.
contract LaneExecutor is CCIPReceiver, Ownable, ILaneExecutor, IReceiver {
    ILaneController private s_laneController;
    ICcipRouter public immutable s_ccipRouter;
    address public creForwarder;

    /// @notice Executor addresses on remote chains, keyed by CCIP chain selector.
    mapping(uint64 => address) public remoteExecutors;
    /// @notice Addresses allowed to send race legs (CRE forwarder, tests).
    mapping(address => bool) public hopSenders;

    bool private _creReportActive;

    event HopSent(
        bytes32 indexed messageId, uint256 indexed roundId, uint8 indexed laneId, uint64 destChainSelector
    );
    event HopReceived(uint256 indexed roundId, uint8 indexed laneId, uint64 sourceChainSelector, uint256 latency);

    error ControllerNotSet();
    error UnknownDestination(uint64 destChainSelector);
    error UnknownSource(uint64 sourceChainSelector);
    error UnauthorizedSource(address sender, address expected);
    error NotAuthorized();
    error ReportExecutionFailed();

    modifier onlyHopSender() {
        if (!_creReportActive && msg.sender != owner() && !hopSenders[msg.sender]) {
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
        s_laneController = ILaneController(controller);
    }

    function setRemoteExecutor(uint64 chainSelector, address executor) external onlyOwner {
        remoteExecutors[chainSelector] = executor;
    }

    function setHopSender(address sender, bool allowed) external onlyOwner {
        hopSenders[sender] = allowed;
    }

    function setCreForwarder(address forwarder) external onlyOwner {
        creForwarder = forwarder;
    }

    /// @inheritdoc IReceiver
    function onReport(bytes calldata, bytes calldata report) external {
        if (msg.sender != creForwarder) revert NotAuthorized();
        CreReportAuth.assertExecutorReport(report);
        _creReportActive = true;
        (bool ok,) = address(this).call(report);
        _creReportActive = false;
        if (!ok) revert ReportExecutionFailed();
    }

    /// @notice Sends one race leg to the executor on the destination chain.
    /// @dev Fee is paid in native token from this contract's balance (fund via `receive`).
    function sendHop(uint256 roundId, uint8 laneId, uint64 destChainSelector)
        external
        onlyHopSender
        returns (bytes32 messageId)
    {
        address destExecutor = remoteExecutors[destChainSelector];
        if (destExecutor == address(0)) revert UnknownDestination(destChainSelector);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destExecutor),
            data: abi.encode(roundId, laneId, block.timestamp),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: address(0)
        });

        uint256 fee = s_ccipRouter.getFee(destChainSelector, message);
        messageId = s_ccipRouter.ccipSend{value: fee}(destChainSelector, message);
        emit HopSent(messageId, roundId, laneId, destChainSelector);
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        if (address(s_laneController) == address(0)) revert ControllerNotSet();

        address expectedSender = remoteExecutors[message.sourceChainSelector];
        if (expectedSender == address(0)) revert UnknownSource(message.sourceChainSelector);

        address sender = abi.decode(message.sender, (address));
        if (sender != expectedSender) revert UnauthorizedSource(sender, expectedSender);

        (uint256 roundId, uint8 laneId, uint256 sendTime) = abi.decode(message.data, (uint256, uint8, uint256));
        if (sendTime > block.timestamp) revert InvalidSendTime();

        uint256 latency = block.timestamp - sendTime;

        emit HopReceived(roundId, laneId, message.sourceChainSelector, latency);
        s_laneController.recordHop(roundId, laneId, message.sourceChainSelector, sendTime);
    }

    error InvalidSendTime();
}
