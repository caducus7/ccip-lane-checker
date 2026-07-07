// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {CCIPReceiver} from "@chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICcipRouter} from "../interfaces/ICcipRouter.sol";

/// @title LaneToken
/// @notice Solo latency-challenge mode: one player races tokens across CCIP hops.
/// @dev VRF v2.5 hop randomness is on-chain verifiable (fair for players).
///      CCIP access goes through `ICcipRouter` — the single swap point for vNext.
contract LaneToken is CCIPReceiver, VRFConsumerBaseV2Plus {
    struct GameRound {
        address initiator;
        uint8 hopCount;
        uint8 maxHops;
        uint256 totalLatency;
        uint256 lastSendTime;
        uint256 amount;
        bool isActive;
    }

    IERC20 public immutable i_underlyingToken;
    mapping(address => uint256) public s_balances;

    uint256 private immutable i_vrfSubscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private constant CALLBACK_GAS_LIMIT = 100_000;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 public s_gameCounter;
    mapping(uint256 => GameRound) public s_gameRounds;
    mapping(bytes32 => uint256) public s_messageIdToGameId;
    mapping(uint256 => uint256) public s_vrfRequestToGameId;
    uint256[] public s_supportedChainSelectors;
    ICcipRouter public immutable s_router;

    /// @notice Trusted LaneToken peers per source chain (CCIP message.sender allowlist).
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

    error NotAdmin();
    error UnknownSource(uint64 sourceChainSelector);
    error UnauthorizedSource(address sender, address expected);

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
        uint256[] memory supportedChains
    ) CCIPReceiver(router) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_underlyingToken = IERC20(underlyingToken);
        i_vrfSubscriptionId = vrfSubscriptionId;
        i_gasLane = gasLane;
        s_supportedChainSelectors = supportedChains;
        s_router = ICcipRouter(router);
        admin = msg.sender;
    }

    function setRemoteLaneToken(uint64 chainSelector, address laneToken) external onlyAdmin {
        remoteLaneTokens[chainSelector] = laneToken;
        emit RemoteLaneTokenSet(chainSelector, laneToken);
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "zero admin");
        admin = newAdmin;
    }

    function deposit(uint256 amount) external {
        i_underlyingToken.transferFrom(msg.sender, address(this), amount);
        s_balances[msg.sender] += amount;
        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        require(s_balances[msg.sender] >= amount, "Insufficient balance");
        s_balances[msg.sender] -= amount;
        i_underlyingToken.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function startGame(uint64 destinationChainSelector, uint256 amount, uint8 maxHops) external returns (bytes32 messageId) {
        require(s_balances[msg.sender] >= amount, "Insufficient balance");
        s_balances[msg.sender] -= amount;

        s_gameCounter++;
        uint256 gameId = s_gameCounter;

        s_gameRounds[gameId] = GameRound({
            initiator: msg.sender,
            hopCount: 0,
            maxHops: maxHops,
            totalLatency: 0,
            lastSendTime: block.timestamp,
            amount: amount,
            isActive: true
        });

        bytes memory messageData = abi.encode(gameId, block.timestamp);
        messageId = _bridge(destinationChainSelector, amount, messageData);
        s_messageIdToGameId[messageId] = gameId;

        emit GameRoundStarted(gameId, msg.sender, amount, maxHops);
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        address expectedSender = remoteLaneTokens[message.sourceChainSelector];
        if (expectedSender == address(0)) revert UnknownSource(message.sourceChainSelector);

        address sender = abi.decode(message.sender, (address));
        if (sender != expectedSender) revert UnauthorizedSource(sender, expectedSender);

        (uint256 gameId, uint256 sendTime) = abi.decode(message.data, (uint256, uint256));
        GameRound storage round = s_gameRounds[gameId];
        require(round.isActive, "Game is not active");
        require(sendTime <= block.timestamp, "future sendTime");

        uint256 latency = block.timestamp - sendTime;
        round.totalLatency += latency;
        round.hopCount++;

        emit HopCompleted(gameId, message.sourceChainSelector, latency, round.hopCount);

        if (round.hopCount >= round.maxHops) {
            round.isActive = false;
            s_balances[round.initiator] += round.amount;
            emit GameFinished(gameId, round.totalLatency, round.hopCount);
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

        uint256 randomIndex = randomWords[0] % s_supportedChainSelectors.length;
        uint64 nextChainSelector = uint64(s_supportedChainSelectors[randomIndex]);
        round.lastSendTime = block.timestamp;

        bytes memory messageData = abi.encode(gameId, round.lastSendTime);
        bytes32 messageId = _bridge(nextChainSelector, round.amount, messageData);
        s_messageIdToGameId[messageId] = gameId;
    }

    function _bridge(uint64 destinationChainSelector, uint256 amount, bytes memory messageData)
        internal
        returns (bytes32 messageId)
    {
        i_underlyingToken.approve(address(s_router), amount);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(i_underlyingToken), amount: amount});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(this)),
            data: messageData,
            tokenAmounts: tokenAmounts,
            extraArgs: "",
            feeToken: address(0)
        });

        uint256 fee = s_router.getFee(destinationChainSelector, message);
        messageId = s_router.ccipSend{value: fee}(destinationChainSelector, message);
        emit BridgeStarted(messageId, destinationChainSelector, amount);
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
