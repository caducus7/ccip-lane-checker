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

    /// @notice Default gas for destination `ccipReceive` execution.
    uint256 public constant CCIP_RECEIVE_GAS_LIMIT = 500_000;

    mapping(uint64 => address) public remoteExecutors;
    mapping(address => bool) public hopSenders;
    mapping(bytes32 => bool) private s_deliveredMessageIds;
    /// @notice When true, allow wiring foreign selectors to `address(this)` and CCIP-Local hop attribution (tests/sim only).
    bool public allowCcipLocalLoopback;

    mapping(bytes32 => bool) public allowedWorkflowIds;
    mapping(bytes10 => bool) public allowedWorkflowNames;
    mapping(address => bool) public allowedWorkflowOwners;
    bool public workflowIdAllowlistActive;
    bool public workflowNameAllowlistActive;
    bool public workflowOwnerAllowlistActive;

    event HopSent(
        bytes32 indexed messageId, uint256 indexed roundId, uint8 indexed laneId, uint64 destChainSelector
    );
    event HopReceived(uint256 indexed roundId, uint8 indexed laneId, uint64 sourceChainSelector, uint256 latency);
    event HopRelayed(bytes32 indexed messageId, uint256 indexed roundId, uint8 indexed laneId);
    event LocalHopRecorded(uint256 indexed roundId, uint8 indexed laneId, uint64 chainSelector);
    event WorkflowIdAllowlistUpdated(bytes32 workflowId, bool allowed);
    event WorkflowNameAllowlistUpdated(bytes10 workflowName, bool allowed);
    event WorkflowOwnerAllowlistUpdated(address workflowOwner, bool allowed);

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
    error DuplicateMessage(bytes32 messageId);
    error InvalidHopChainSelector(uint64 provided, uint64 local, uint64 source);
    error InvalidHopDestination(uint64 destChainSelector);
    error InvalidRoundState();
    error SelfWireForbidden(uint64 chainSelector);

    uint256 public constant MAX_CLOCK_SKEW = 15 minutes;

    modifier onlyHopSender() {
        if (
            msg.sender != owner() && !hopSenders[msg.sender] && msg.sender != creForwarder
                && msg.sender != address(this)
        ) {
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
        if (
            executor == address(this) && chainSelector != localChainSelector && !allowCcipLocalLoopback
        ) {
            revert SelfWireForbidden(chainSelector);
        }
        remoteExecutors[chainSelector] = executor;
    }

    function setAllowCcipLocalLoopback(bool allowed) external onlyOwner {
        allowCcipLocalLoopback = allowed;
    }

    function setHopSender(address sender, bool allowed) external onlyOwner {
        hopSenders[sender] = allowed;
    }

    function setCreForwarder(address forwarder) external onlyOwner {
        if (forwarder == address(0)) revert ZeroAddress();
        address oldForwarder = creForwarder;
        creForwarder = forwarder;
        if (oldForwarder != address(0)) {
            hopSenders[oldForwarder] = false;
        }
        hopSenders[forwarder] = true;
    }

    function setAllowedWorkflowId(bytes32 workflowId, bool allowed) external onlyOwner {
        allowedWorkflowIds[workflowId] = allowed;
        if (allowed) workflowIdAllowlistActive = true;
        emit WorkflowIdAllowlistUpdated(workflowId, allowed);
    }

    function setAllowedWorkflowName(bytes10 workflowName, bool allowed) external onlyOwner {
        allowedWorkflowNames[workflowName] = allowed;
        if (allowed) workflowNameAllowlistActive = true;
        emit WorkflowNameAllowlistUpdated(workflowName, allowed);
    }

    function setAllowedWorkflowOwner(address workflowOwner, bool allowed) external onlyOwner {
        if (workflowOwner == address(0)) revert ZeroAddress();
        allowedWorkflowOwners[workflowOwner] = allowed;
        if (allowed) workflowOwnerAllowlistActive = true;
        emit WorkflowOwnerAllowlistUpdated(workflowOwner, allowed);
    }

    function clearWorkflowAllowlistFlags() external onlyOwner {
        workflowIdAllowlistActive = false;
        workflowNameAllowlistActive = false;
        workflowOwnerAllowlistActive = false;
    }

    /// @notice ERC-165: IReceiver (Keystone) + CCIP receiver interfaces.
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IReceiver).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IReceiver
    function onReport(bytes calldata metadata, bytes calldata report) external whenNotPaused nonReentrant {
        if (msg.sender != creForwarder) revert NotAuthorized();
        CreReportAuth.assertMetadata(
            metadata,
            workflowIdAllowlistActive,
            workflowNameAllowlistActive,
            workflowOwnerAllowlistActive,
            allowedWorkflowIds,
            allowedWorkflowNames,
            allowedWorkflowOwners
        );
        CreReportAuth.assertExecutorReport(report);
        // Inline sendHop — external self-call would reenter the nonReentrant lock.
        (uint256 roundId, uint8 laneId, uint64 destChainSelector) =
            abi.decode(report[4:], (uint256, uint8, uint64));
        _sendHop(roundId, laneId, destChainSelector);
    }

    function sendHop(uint256 roundId, uint8 laneId, uint64 destChainSelector)
        external
        onlyHopSender
        whenNotPaused
        nonReentrant
        returns (bytes32 messageId)
    {
        return _sendHop(roundId, laneId, destChainSelector);
    }

    function _sendHop(uint256 roundId, uint8 laneId, uint64 destChainSelector) internal returns (bytes32 messageId) {
        _assertHopDestination(roundId, laneId, destChainSelector);

        // Path hop on this chain: record locally (home) or relay (spoke) without CCIP self-send.
        if (destChainSelector == localChainSelector) {
            if (localChainSelector == homeChainSelector) {
                if (canonicalController == address(0)) revert HomeConfigNotSet();
                if (IPausable(canonicalController).paused()) revert HomeControllerPaused();
                ILaneController(canonicalController).recordHop(
                    roundId, laneId, localChainSelector, block.timestamp
                );
                emit LocalHopRecorded(roundId, laneId, localChainSelector);
                // Same signature as CCIP path so CRE hop-sender continuation triggers fire.
                emit HopReceived(roundId, laneId, localChainSelector, 0);
                return bytes32(0);
            }
            messageId = _relayHopToHome(roundId, laneId, localChainSelector, block.timestamp);
            return messageId;
        }

        address destExecutor = remoteExecutors[destChainSelector];
        if (destExecutor == address(0)) revert UnknownDestination(destChainSelector);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destExecutor),
            data: abi.encode(roundId, laneId, destChainSelector, block.timestamp),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: CCIP_RECEIVE_GAS_LIMIT})),
            feeToken: address(0)
        });

        messageId = _ccipSend(destChainSelector, message);
        emit HopSent(messageId, roundId, laneId, destChainSelector);
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override whenNotPaused {
        if (canonicalController == address(0)) revert HomeConfigNotSet();
        if (message.messageId == bytes32(0)) revert DuplicateMessage(message.messageId);
        if (s_deliveredMessageIds[message.messageId]) revert DuplicateMessage(message.messageId);

        address expectedSender = remoteExecutors[message.sourceChainSelector];
        if (expectedSender == address(0)) revert UnknownSource(message.sourceChainSelector);

        address sender = abi.decode(message.sender, (address));
        if (sender != expectedSender) revert UnauthorizedSource(sender, expectedSender);

        (uint256 roundId, uint8 laneId,, uint256 sendTime) =
            abi.decode(message.data, (uint256, uint8, uint64, uint256));
        if (sendTime > block.timestamp + MAX_CLOCK_SKEW) revert InvalidSendTime();

        uint256 latency = sendTime > block.timestamp ? 0 : block.timestamp - sendTime;
        emit HopReceived(roundId, laneId, message.sourceChainSelector, latency);

        if (localChainSelector == homeChainSelector) {
            if (IPausable(canonicalController).paused()) revert HomeControllerPaused();
            // Direct hop onto home → local; relay from spoke → source chain completed the hop.
            uint64 hopChainSelector = _resolveHomeHopSelector(message);
            uint256 recorded = sendTime > block.timestamp ? block.timestamp : sendTime;
            ILaneController(canonicalController).recordHop(roundId, laneId, hopChainSelector, recorded);
        } else {
            // Spoke always reports its own chain — never the untrusted payload selector.
            // Relay before marking delivered so a failed send can be retried via re-delivery.
            _relayHopToHome(roundId, laneId, localChainSelector, sendTime);
        }
        s_deliveredMessageIds[message.messageId] = true;
    }

    function _resolveHomeHopSelector(Client.Any2EVMMessage memory message) internal view returns (uint64) {
        (, , uint64 claimedSelector,) = abi.decode(message.data, (uint256, uint8, uint64, uint256));
        if (claimedSelector == localChainSelector) {
            return localChainSelector;
        }
        if (claimedSelector == message.sourceChainSelector) {
            return message.sourceChainSelector;
        }
        // Same-chain CCIP Local loopback: only when explicitly enabled (tests/sim).
        if (
            allowCcipLocalLoopback && message.sourceChainSelector == localChainSelector
                && remoteExecutors[claimedSelector] != address(0)
        ) {
            return claimedSelector;
        }
        revert InvalidHopChainSelector(claimedSelector, localChainSelector, message.sourceChainSelector);
    }

    function _relayHopToHome(uint256 roundId, uint8 laneId, uint64 hopChainSelector, uint256 sendTime)
        internal
        returns (bytes32 messageId)
    {
        if (homeExecutor == address(0)) revert HomeConfigNotSet();

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(homeExecutor),
            data: abi.encode(roundId, laneId, hopChainSelector, sendTime),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: CCIP_RECEIVE_GAS_LIMIT})),
            feeToken: address(0)
        });

        messageId = _ccipSend(homeChainSelector, message);
        emit HopRelayed(messageId, roundId, laneId);
    }

    function _assertHopDestination(uint256 roundId, uint8 laneId, uint64 destChainSelector) internal view {
        // Spoke / unset controller: require wired dest (or local self-hop for relay).
        if (address(s_laneController) == address(0) || localChainSelector != homeChainSelector) {
            if (destChainSelector != localChainSelector && remoteExecutors[destChainSelector] == address(0)) {
                revert UnknownDestination(destChainSelector);
            }
            return;
        }

        (bool ok, bytes memory ret) =
            address(s_laneController).staticcall(abi.encodeWithSignature("getRoundState(uint256)", roundId));
        if (!ok || ret.length < 32) revert InvalidRoundState();
        uint8 state = abi.decode(ret, (uint8));
        // Racing=1, Finished=2 — keep recording runner-up hops while Finished.
        if (state != 1 && state != 2) revert InvalidRoundState();

        (uint64[] memory path, uint8 hopsCompleted,,,, bool finished) = s_laneController.getLane(roundId, laneId);
        if (finished || hopsCompleted >= path.length) revert InvalidHopDestination(destChainSelector);
        if (path[hopsCompleted] != destChainSelector) revert InvalidHopDestination(destChainSelector);
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
