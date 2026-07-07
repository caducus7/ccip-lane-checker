// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LaneToken} from "../src/core/LaneToken.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockCCIPRouter} from "../src/mocks/MockCCIPRouter.sol";
import {MockVRFCoordinatorV2Plus} from "../src/mocks/MockVRFCoordinatorV2Plus.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

contract LaneTokenTest is Test {
    LaneToken public laneToken;
    MockERC20 public mockUsdc;
    MockCCIPRouter public mockRouter;
    MockVRFCoordinatorV2Plus public mockVrfCoordinator;

    address public player = makeAddr("player");
    address public mumbaiPeer = makeAddr("mumbaiPeer");
    address public fujiPeer = makeAddr("fujiPeer");

    uint64 constant MUMBAI_SELECTOR = 12532609583862916517;
    uint64 constant FUJI_SELECTOR = 14767482510784806043;
    uint256 constant START_AMOUNT = 10 * 1e6;

    event GameRoundStarted(uint256 indexed gameId, address indexed initiator, uint256 amount, uint8 maxHops);
    event BridgeStarted(bytes32 indexed messageId, uint64 destChainSelector, uint256 amount);
    event HopCompleted(uint256 indexed gameId, uint64 fromChain, uint256 latency, uint8 hopCount);
    event GameFinished(uint256 indexed gameId, uint256 totalLatency, uint8 totalHops);
    event NextHopRequested(uint256 indexed requestId);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        mockUsdc = new MockERC20("Mock USDC", "mUSDC", 6);
        mockRouter = new MockCCIPRouter();
        mockVrfCoordinator = new MockVRFCoordinatorV2Plus();

        uint256[] memory supportedChains = new uint256[](2);
        supportedChains[0] = MUMBAI_SELECTOR;
        supportedChains[1] = FUJI_SELECTOR;

        laneToken = new LaneToken(
            address(mockRouter),
            address(mockUsdc),
            address(mockVrfCoordinator),
            1,
            bytes32(0),
            supportedChains
        );
        laneToken.setRemoteLaneToken(MUMBAI_SELECTOR, mumbaiPeer);
        laneToken.setRemoteLaneToken(FUJI_SELECTOR, fujiPeer);

        mockUsdc.mint(player, START_AMOUNT);
        vm.startPrank(player);
        mockUsdc.approve(address(laneToken), START_AMOUNT);
        laneToken.deposit(START_AMOUNT);
        vm.stopPrank();
    }

    function test_StartGame() public {
        vm.startPrank(player);

        vm.expectEmit(true, true, false, true);
        emit Approval(address(laneToken), address(mockRouter), START_AMOUNT);
        vm.expectEmit(true, true, false, false);
        emit BridgeStarted(bytes32(uint256(1)), MUMBAI_SELECTOR, START_AMOUNT);
        vm.expectEmit(true, true, false, false);
        emit GameRoundStarted(1, player, START_AMOUNT, 3);

        laneToken.startGame(MUMBAI_SELECTOR, START_AMOUNT, 3);
        vm.stopPrank();

        (,,,,,, bool isActive) = laneToken.getGameRound(1);
        assertTrue(isActive);
    }

    function test_FullMultiHopGame() public {
        uint8 maxHops = 2;

        vm.prank(player);
        laneToken.startGame(MUMBAI_SELECTOR, START_AMOUNT, maxHops);

        uint256 gameId = 1;
        (,,,,, uint256 lastSendTime,) = laneToken.getGameRound(gameId);

        uint256 timePassed = 300;
        vm.warp(block.timestamp + timePassed);

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(0x123)),
            sourceChainSelector: MUMBAI_SELECTOR,
            sender: abi.encode(mumbaiPeer),
            data: abi.encode(gameId, lastSendTime),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.expectEmit(true, true, false, false);
        emit HopCompleted(gameId, MUMBAI_SELECTOR, timePassed, 1);
        vm.expectEmit(true, false, false, true);
        emit NextHopRequested(1);
        vm.prank(address(mockRouter));
        laneToken.ccipReceive(message);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 99;
        mockVrfCoordinator.fulfillRandomWords(1, address(laneToken), randomWords);

        vm.warp(block.timestamp + timePassed);
        message.data = abi.encode(gameId, block.timestamp - timePassed);
        message.sourceChainSelector = FUJI_SELECTOR;
        message.sender = abi.encode(fujiPeer);

        vm.expectEmit(true, true, false, false);
        emit HopCompleted(gameId, FUJI_SELECTOR, timePassed, 2);
        vm.expectEmit(true, true, false, false);
        emit GameFinished(gameId, timePassed * 2, 2);
        vm.prank(address(mockRouter));
        laneToken.ccipReceive(message);

        (,,,,,, bool isActive) = laneToken.getGameRound(gameId);
        assertFalse(isActive);
    }
}
