// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {CCIPReceiver} from "@chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICcipRouter} from "../interfaces/ICcipRouter.sol";
import {StandardTokenTransfer} from "../libraries/StandardTokenTransfer.sol";

/// @title LaneToken
/// @notice Solo latency-challenge mode: one player races tokens across CCIP hops.
/// @dev VRF v2.5 hop randomness is on-chain verifiable. Only standard ERC20 underlying
///      tokens are supported (no fee-on-transfer). Cross-chain games are keyed by a
///      globally unique foreign key (origin chain, origin contract, origin game id).
contract LaneToken is CCIPReceiver, VRFConsumerBaseV2Plus {
    using SafeERC20 for IERC20;
    using StandardTokenTransfer for IERC20;

    struct GameRound {
        address initiator;
        uint8 hopCount;
        uint8 maxHops;
        bool isActive;
        bool tokensBridgedOut;
        uint256 totalLatency;
        uint256 lastSendTime;
        uint256 amount;
        bytes32 foreignKey;
        uint64 originChainSelector;
        address originToken;
        uint256 originGameId;
    }

    IERC20 public immutable i_underlyingToken;
    uint256 private immutable i_chainId;
    uint64 private immutable i_localChainSelector;
    mapping(address => uint256) public s_balances;
    uint256 public s_totalBooked;
    uint256 public s_tokensInPlay;

    uint256 private immutable i_vrfSubscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private constant CALLBACK_GAS_LIMIT = 1_500_000;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 public s_gameCounter;
    mapping(uint256 => GameRound) public s_gameRounds;
    mapping(bytes32 => uint256) public s_foreignKeyToGameId;
    mapping(bytes32 => bool) public s_foreignKeySettled;
    mapping(bytes32 => uint256) public s_messageIdToGameId;
    mapping(bytes32 => bool) private s_deliveredMessageIds;
    mapping(uint256 => uint256) public s_vrfRequestToGameId;
    uint256[] public s_supportedChainSelectors;
    ICcipRouter public immutable s_router;

    mapping(uint64 => address) public remoteLaneTokens;
    address public admin;

    event RemoteLaneTokenSet(uint64 indexed chainSelector, address laneToken);

    event GameRoundStarted(uint256 indexed gameId, address indexed initiator, uint256 amount, uint8 maxHops);
    event HopCompleted(uint256 indexed gameId, uint64 fromChain, uint256 latency, uint8 hopCount);
    event GameFinished(uint256 indexed gameId, uint256 totalLatency, uint8 totalHops);
    event BridgeStarted(bytes32 indexed messageId, uint64 destChainSelector, uint256 amount);
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event NextHopRequested(uint256 indexed requestId);
    event GameAbandoned(uint256 indexed gameId, address indexed initiator, uint256 amount);
    event SettlementPropagationSkipped(uint64 indexed chainSelector, uint256 requiredFee, uint256 available);
    event LateHopRefunded(bytes32 indexed foreignKey, address indexed initiator, uint256 amount);

    error NotAdmin();
    error UnknownSource(uint64 sourceChainSelector);
    error UnauthorizedSource(address sender, address expected);
    error InvalidZeroAddress();
    error GameMismatch();
    error InsufficientLiquidity();
    error InvalidMaxHops();
    error InvalidAmount();
    error GameNotAbandonable();
    error NotInitiator();
    error InsufficientCcipFee(uint256 required, uint256 available);
    error UnwiredRemoteLaneToken(uint64 chainSelector);
    error DuplicateMessage(bytes32 messageId);
    error BridgeCustodyMismatch();
    error AlreadySettled(bytes32 foreignKey);
    error SelfBridgeForbidden(uint64 chainSelector);
    error NoWiredDestinations();

    bytes32 private constant SETTLEMENT_MESSAGE_TAG = keccak256("LaneToken.Settlement");

    uint8 public constant MAX_HOPS = 16;
    uint256 public constant GAME_ABANDON_TIMEOUT = 7 days;
    uint256 public constant MAX_CLOCK_SKEW = 15 minutes;
    uint256 public constant CCIP_RECEIVE_GAS_LIMIT = 500_000;

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    constructor(
        address router,
        address underlyingToken,
        address vrfCoordinator,
        uint256 vrfSubscriptionId,
        bytes32 gasLane,
        uint256 chainId,
        uint64 localChainSelector,
        uint256[] memory supportedChains
    ) CCIPReceiver(router) VRFConsumerBaseV2Plus(vrfCoordinator) {
        if (router == address(0) || underlyingToken == address(0) || vrfCoordinator == address(0)) {
            revert InvalidZeroAddress();
        }
        require(supportedChains.length > 0, "no supported chains");
        i_underlyingToken = IERC20(underlyingToken);
        i_chainId = chainId;
        i_localChainSelector = localChainSelector;
        i_vrfSubscriptionId = vrfSubscriptionId;
        i_gasLane = gasLane;
        s_supportedChainSelectors = supportedChains;
        s_router = ICcipRouter(router);
        admin = msg.sender;
    }

    receive() external payable {}

    function setRemoteLaneToken(uint64 chainSelector, address laneToken) external onlyAdmin {
        remoteLaneTokens[chainSelector] = laneToken;
        emit RemoteLaneTokenSet(chainSelector, laneToken);
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "zero admin");
        admin = newAdmin;
        // ConfirmedOwnerWithProposal: new admin must call acceptOwnership() to take coordinator rights.
        transferOwnership(newAdmin);
    }

    function deposit(uint256 amount) external {
        i_underlyingToken.transferFromExact(msg.sender, address(this), amount);
        s_balances[msg.sender] += amount;
        s_totalBooked += amount;
        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        require(s_balances[msg.sender] >= amount, "Insufficient balance");
        require(i_underlyingToken.balanceOf(address(this)) >= amount, "pool illiquid");
        s_balances[msg.sender] -= amount;
        s_totalBooked -= amount;
        require(
            i_underlyingToken.balanceOf(address(this)) >= s_totalBooked + s_tokensInPlay,
            "pool illiquid"
        );
        i_underlyingToken.transferExact(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function startGame(uint64 destinationChainSelector, uint256 amount, uint8 maxHops) external returns (bytes32 messageId) {
        if (amount == 0) revert InvalidAmount();
        if (maxHops == 0 || maxHops > MAX_HOPS) revert InvalidMaxHops();
        if (remoteLaneTokens[destinationChainSelector] == address(0)) {
            revert UnwiredRemoteLaneToken(destinationChainSelector);
        }
        require(s_balances[msg.sender] >= amount, "Insufficient balance");
        s_balances[msg.sender] -= amount;
        s_totalBooked -= amount;
        s_tokensInPlay += amount;

        uint256 gameId = ++s_gameCounter;
        bytes32 foreignKey = _foreignKey(gameId);

        s_gameRounds[gameId] = GameRound({
            initiator: msg.sender,
            hopCount: 0,
            maxHops: maxHops,
            isActive: true,
            tokensBridgedOut: false,
            totalLatency: 0,
            lastSendTime: block.timestamp,
            amount: amount,
            foreignKey: foreignKey,
            originChainSelector: i_localChainSelector,
            originToken: address(this),
            originGameId: gameId
        });
        s_foreignKeyToGameId[foreignKey] = gameId;

        bytes memory messageData = _encodeHopMessage(gameId, block.timestamp);
        messageId = _bridge(destinationChainSelector, amount, messageData, gameId);
        s_messageIdToGameId[messageId] = gameId;

        emit GameRoundStarted(gameId, msg.sender, amount, maxHops);
    }

    /// @notice Refund a stuck game after no hop progress for `GAME_ABANDON_TIMEOUT`.
    function abandonGame(uint256 gameId) external {
        GameRound storage round = s_gameRounds[gameId];
        if (!round.isActive || round.tokensBridgedOut) revert GameNotAbandonable();
        if (msg.sender != round.initiator) revert NotInitiator();
        if (block.timestamp <= round.lastSendTime + GAME_ABANDON_TIMEOUT) revert GameNotAbandonable();

        round.isActive = false;
        s_tokensInPlay -= round.amount;
        s_balances[round.initiator] += round.amount;
        s_totalBooked += round.amount;
        emit GameAbandoned(gameId, round.initiator, round.amount);
    }

    struct HopPayload {
        bytes32 foreignKey;
        uint64 originChainSelector;
        address originToken;
        uint256 originGameId;
        address initiator;
        uint256 amount;
        uint8 maxHops;
        uint256 sendTime;
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        if (message.messageId == bytes32(0)) revert DuplicateMessage(message.messageId);
        if (s_deliveredMessageIds[message.messageId]) revert DuplicateMessage(message.messageId);
        s_deliveredMessageIds[message.messageId] = true;

        uint64 sourceSelector = message.sourceChainSelector;
        address expectedSender = remoteLaneTokens[sourceSelector];
        if (expectedSender == address(0)) revert UnknownSource(sourceSelector);

        address sender = abi.decode(message.sender, (address));
        if (sender != expectedSender) revert UnauthorizedSource(sender, expectedSender);

        if (_isSettlementMessage(message.data)) {
            if (message.destTokenAmounts.length != 0) revert GameMismatch();
            _handleSettlementMessage(message.data);
            return;
        }

        HopPayload memory payload = abi.decode(message.data, (HopPayload));
        if (payload.sendTime > block.timestamp + MAX_CLOCK_SKEW) revert("future sendTime");

        _verifyInboundTokens(message, payload.amount);

        uint256 gameId = _resolveInboundGameId(payload);
        if (gameId == 0) {
            // Late hop after settlement: tokens already credited to initiator.
            return;
        }
        _recordHop(gameId, payload, sourceSelector);
    }

    function _resolveInboundGameId(HopPayload memory payload) internal returns (uint256 gameId) {
        gameId = s_foreignKeyToGameId[payload.foreignKey];
        if (gameId == 0) {
            if (s_foreignKeySettled[payload.foreignKey]) {
                // Do not bootstrap tokensInPlay after settlement; refund initiator on this chain.
                s_balances[payload.initiator] += payload.amount;
                s_totalBooked += payload.amount;
                emit LateHopRefunded(payload.foreignKey, payload.initiator, payload.amount);
                return 0;
            }
            return _bootstrapInboundGame(payload);
        }

        GameRound storage existing = s_gameRounds[gameId];
        if (
            existing.initiator != payload.initiator || existing.amount != payload.amount
                || existing.maxHops != payload.maxHops || existing.foreignKey != payload.foreignKey
        ) revert GameMismatch();
    }

    function _recordHop(uint256 gameId, HopPayload memory payload, uint64 sourceSelector) internal {
        if (s_foreignKeySettled[payload.foreignKey]) {
            GameRound storage settled = s_gameRounds[gameId];
            settled.isActive = false;
            settled.tokensBridgedOut = false;
            // Book inbound surplus to admin — initiator was already paid on the finishing chain.
            if (payload.amount > 0) {
                s_balances[admin] += payload.amount;
                s_totalBooked += payload.amount;
                emit LateHopRefunded(payload.foreignKey, admin, payload.amount);
            }
            return;
        }

        GameRound storage round = s_gameRounds[gameId];
        if (!round.isActive && round.tokensBridgedOut && round.hopCount < round.maxHops) {
            round.isActive = true;
            round.tokensBridgedOut = false;
            s_tokensInPlay += round.amount;
        }
        require(round.isActive, "Game is not active");
        round.lastSendTime = block.timestamp;

        uint256 latency = payload.sendTime > block.timestamp ? 0 : block.timestamp - payload.sendTime;
        round.totalLatency += latency;
        round.hopCount += 1;

        emit HopCompleted(gameId, sourceSelector, latency, round.hopCount);

        if (round.hopCount >= round.maxHops) {
            _finishGame(gameId, round.foreignKey, round.initiator, round.amount, round.totalLatency, round.hopCount);
            return;
        }

        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_gasLane,
                subId: i_vrfSubscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: CALLBACK_GAS_LIMIT,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
            })
        );
        s_vrfRequestToGameId[requestId] = gameId;
        emit NextHopRequested(requestId);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        uint256 gameId = s_vrfRequestToGameId[requestId];
        require(gameId != 0, "Invalid VRF request");

        GameRound storage round = s_gameRounds[gameId];
        require(round.isActive, "Game is not active");

        uint64 nextChainSelector = _pickWiredDestination(randomWords[0]);
        round.lastSendTime = block.timestamp;

        bytes memory messageData = _encodeHopMessage(gameId, round.lastSendTime);
        bytes32 messageId = _bridge(nextChainSelector, round.amount, messageData, gameId);
        s_messageIdToGameId[messageId] = gameId;
    }

    /// @dev Prefer remote wired peers; fall back to local self-loop when that is the only wiring.
    function _pickWiredDestination(uint256 entropy) internal view returns (uint64) {
        uint256 len = s_supportedChainSelectors.length;
        uint256 wiredCount;
        for (uint256 i = 0; i < len; i++) {
            uint64 selector = uint64(s_supportedChainSelectors[i]);
            address remote = remoteLaneTokens[selector];
            if (remote == address(0)) continue;
            if (remote == address(this) && selector != i_localChainSelector) continue;
            if (selector == i_localChainSelector && remote != address(this)) continue;
            // Skip local unless no foreign peer exists (filled in second pass).
            if (selector == i_localChainSelector) continue;
            wiredCount++;
        }

        if (wiredCount == 0) {
            if (remoteLaneTokens[i_localChainSelector] == address(this)) {
                return i_localChainSelector;
            }
            revert NoWiredDestinations();
        }

        uint256 target = entropy % wiredCount;
        uint256 seen;
        for (uint256 i = 0; i < len; i++) {
            uint64 selector = uint64(s_supportedChainSelectors[i]);
            if (selector == i_localChainSelector) continue;
            address remote = remoteLaneTokens[selector];
            if (remote == address(0)) continue;
            if (remote == address(this)) continue;
            if (seen == target) return selector;
            seen++;
        }
        revert NoWiredDestinations();
    }

    function _bootstrapInboundGame(HopPayload memory payload) internal returns (uint256 gameId) {
        gameId = ++s_gameCounter;
        s_foreignKeyToGameId[payload.foreignKey] = gameId;
        s_tokensInPlay += payload.amount;
        s_gameRounds[gameId] = GameRound({
            initiator: payload.initiator,
            hopCount: 0,
            maxHops: payload.maxHops,
            isActive: true,
            tokensBridgedOut: false,
            totalLatency: 0,
            lastSendTime: payload.sendTime,
            amount: payload.amount,
            foreignKey: payload.foreignKey,
            originChainSelector: payload.originChainSelector,
            originToken: payload.originToken,
            originGameId: payload.originGameId
        });
    }

    function _encodeHopMessage(uint256 gameId, uint256 sendTime) internal view returns (bytes memory) {
        GameRound storage round = s_gameRounds[gameId];
        HopPayload memory payload = HopPayload({
            foreignKey: round.foreignKey,
            originChainSelector: round.originChainSelector,
            originToken: round.originToken,
            originGameId: round.originGameId,
            initiator: round.initiator,
            amount: round.amount,
            maxHops: round.maxHops,
            sendTime: sendTime
        });
        return abi.encode(payload);
    }

    function _foreignKey(uint256 originGameId) internal view returns (bytes32) {
        return keccak256(abi.encode(i_chainId, address(this), originGameId));
    }

    function _verifyInboundTokens(Client.Any2EVMMessage memory message, uint256 expectedAmount) internal view {
        uint256 received;
        for (uint256 i = 0; i < message.destTokenAmounts.length; i++) {
            Client.EVMTokenAmount memory tokenAmount = message.destTokenAmounts[i];
            if (tokenAmount.token == address(i_underlyingToken)) {
                received += tokenAmount.amount;
            }
        }
        if (received != expectedAmount) revert GameMismatch();
    }

    function _bridgeReceiver(uint64 destinationChainSelector) internal view returns (address receiver) {
        address remote = remoteLaneTokens[destinationChainSelector];
        if (remote == address(0)) revert UnwiredRemoteLaneToken(destinationChainSelector);
        // Same-chain loopback (dest == local, receiver == this) is allowed for local sim.
        // Mapping a *foreign* selector to this contract is the WIRE_SELF footgun — forbid it.
        if (remote == address(this) && destinationChainSelector != i_localChainSelector) {
            revert SelfBridgeForbidden(destinationChainSelector);
        }
        return remote;
    }

    function _bridge(uint64 destinationChainSelector, uint256 amount, bytes memory messageData, uint256 gameId)
        internal
        returns (bytes32 messageId)
    {
        address receiver = _bridgeReceiver(destinationChainSelector);
        bool custodyLeavesChain = receiver != address(this);
        uint256 balanceBefore = i_underlyingToken.balanceOf(address(this));

        i_underlyingToken.forceApprove(address(s_router), amount);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(i_underlyingToken), amount: amount});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: messageData,
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: CCIP_RECEIVE_GAS_LIMIT})),
            feeToken: address(0)
        });

        uint256 fee = s_router.getFee(destinationChainSelector, message);
        if (address(this).balance < fee) revert InsufficientCcipFee(fee, address(this).balance);
        messageId = s_router.ccipSend{value: fee}(destinationChainSelector, message);
        emit BridgeStarted(messageId, destinationChainSelector, amount);

        if (!custodyLeavesChain) {
            return messageId;
        }

        uint256 balanceAfter = i_underlyingToken.balanceOf(address(this));
        if (balanceBefore < balanceAfter || balanceBefore - balanceAfter < amount) {
            revert BridgeCustodyMismatch();
        }

        GameRound storage round = s_gameRounds[gameId];
        if (!round.isActive) {
            return messageId;
        }
        round.tokensBridgedOut = true;
        round.isActive = false;
        s_tokensInPlay -= amount;
    }

    function _isSettlementMessage(bytes memory data) internal pure returns (bool) {
        if (data.length < 64) return false;
        (bytes32 tag,) = abi.decode(data, (bytes32, bytes32));
        return tag == SETTLEMENT_MESSAGE_TAG;
    }

    function _handleSettlementMessage(bytes memory data) internal {
        (, bytes32 foreignKey) = abi.decode(data, (bytes32, bytes32));
        _applyForeignKeySettlement(foreignKey);
    }

    function _applyForeignKeySettlement(bytes32 foreignKey) internal {
        if (s_foreignKeySettled[foreignKey]) return;
        s_foreignKeySettled[foreignKey] = true;

        uint256 gameId = s_foreignKeyToGameId[foreignKey];
        if (gameId == 0) return;

        GameRound storage round = s_gameRounds[gameId];
        if (round.isActive) {
            // Freeze only — settlement carries no tokens. Crediting would inflate s_totalBooked
            // without custody. Surplus late hops with tokens book to admin in `_recordHop`.
            round.isActive = false;
            s_tokensInPlay -= round.amount;
        }
        round.tokensBridgedOut = false;
    }

    function _finishGame(
        uint256 gameId,
        bytes32 foreignKey,
        address initiator,
        uint256 amount,
        uint256 totalLatency,
        uint8 totalHops
    ) internal {
        GameRound storage round = s_gameRounds[gameId];
        round.isActive = false;
        round.tokensBridgedOut = false;
        s_tokensInPlay -= amount;

        if (s_foreignKeySettled[foreignKey]) {
            emit GameFinished(gameId, totalLatency, totalHops);
            return;
        }

        s_foreignKeySettled[foreignKey] = true;
        s_balances[initiator] += amount;
        s_totalBooked += amount;
        _propagateSettlement(foreignKey);
        emit GameFinished(gameId, totalLatency, totalHops);
    }

    function _propagateSettlement(bytes32 foreignKey) internal {
        bytes memory data = abi.encode(SETTLEMENT_MESSAGE_TAG, foreignKey);
        uint256 chainCount = s_supportedChainSelectors.length;
        for (uint256 i = 0; i < chainCount; i++) {
            uint64 chainSelector = uint64(s_supportedChainSelectors[i]);
            if (chainSelector == i_localChainSelector) continue;
            address remote = remoteLaneTokens[chainSelector];
            if (remote == address(0) || remote == address(this)) continue;
            _bridgeSettlement(chainSelector, remote, data);
        }
    }

    function _bridgeSettlement(uint64 destinationChainSelector, address receiver, bytes memory messageData)
        internal
    {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: messageData,
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: CCIP_RECEIVE_GAS_LIMIT})),
            feeToken: address(0)
        });

        uint256 fee = s_router.getFee(destinationChainSelector, message);
        if (address(this).balance < fee) {
            emit SettlementPropagationSkipped(destinationChainSelector, fee, address(this).balance);
            return;
        }
        s_router.ccipSend{value: fee}(destinationChainSelector, message);
    }

    function getGameRound(uint256 gameId)
        external
        view
        returns (
            address player,
            uint256 amount,
            uint8 maxHops,
            uint8 hopsCompleted,
            uint256 totalLatency,
            uint256 lastSendTime,
            bool isActive
        )
    {
        GameRound storage round = s_gameRounds[gameId];
        return (
            round.initiator,
            round.amount,
            round.maxHops,
            round.hopCount,
            round.totalLatency,
            round.lastSendTime,
            round.isActive
        );
    }
}
