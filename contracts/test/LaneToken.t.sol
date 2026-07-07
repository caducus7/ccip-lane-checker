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

    uint64 constant LOCAL_SELECTOR = 999_001;
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
            block.chainid,
            LOCAL_SELECTOR,
            supportedChains
        );
        laneToken.setRemoteLaneToken(MUMBAI_SELECTOR, address(laneToken));
        laneToken.setRemoteLaneToken(FUJI_SELECTOR, address(laneToken));

        mockUsdc.mint(player, START_AMOUNT);
        vm.startPrank(player);
        mockUsdc.approve(address(laneToken), START_AMOUNT);
        laneToken.deposit(START_AMOUNT);
        vm.stopPrank();
    }

    function _hopData(
        bytes32 foreignKey,
        uint64 originChainSelector,
        address originToken,
        uint256 originGameId,
        address initiator,
        uint256 amount,
        uint8 maxHops,
        uint256 sendTime
    ) internal pure returns (bytes memory) {
        return abi.encode(
            foreignKey, originChainSelector, originToken, originGameId, initiator, amount, maxHops, sendTime
        );
    }

    function _tokenAmounts(uint256 amount) internal view returns (Client.EVMTokenAmount[] memory) {
        Client.EVMTokenAmount[] memory amounts = new Client.EVMTokenAmount[](1);
        amounts[0] = Client.EVMTokenAmount({token: address(mockUsdc), amount: amount});
        return amounts;
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
        bytes32 foreignKey = keccak256(abi.encode(block.chainid, address(laneToken), gameId));

        uint256 timePassed = 300;
        vm.warp(block.timestamp + timePassed);

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(0x123)),
            sourceChainSelector: MUMBAI_SELECTOR,
            sender: abi.encode(address(laneToken)),
            data: _hopData(
                foreignKey,
                LOCAL_SELECTOR,
                address(laneToken),
                gameId,
                player,
                START_AMOUNT,
                maxHops,
                lastSendTime
            ),
            destTokenAmounts: _tokenAmounts(START_AMOUNT)
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
        message.messageId = bytes32(uint256(0x124));
        message.data = _hopData(
            foreignKey,
            LOCAL_SELECTOR,
            address(laneToken),
            gameId,
            player,
            START_AMOUNT,
            maxHops,
            block.timestamp - timePassed
        );
        message.sourceChainSelector = FUJI_SELECTOR;
        message.sender = abi.encode(address(laneToken));
        message.destTokenAmounts = _tokenAmounts(START_AMOUNT);

        vm.expectEmit(true, true, false, false);
        emit HopCompleted(gameId, FUJI_SELECTOR, timePassed, 2);
        vm.expectEmit(true, true, false, false);
        emit GameFinished(gameId, timePassed * 2, 2);
        vm.prank(address(mockRouter));
        laneToken.ccipReceive(message);

        (,,,,,, bool isActive) = laneToken.getGameRound(gameId);
        assertFalse(isActive);
    }

    function test_gameIdCollision_reverts() public {
        uint256 remoteChainId = 137;
        address remoteToken = makeAddr("remoteToken");
        uint256 originGameId = 42;
        bytes32 foreignKey = keccak256(abi.encode(remoteChainId, remoteToken, originGameId));
        address remoteInitiator = makeAddr("remoteInitiator");
        address otherInitiator = makeAddr("otherInitiator");
        uint8 maxHops = 3;

        Client.Any2EVMMessage memory bootstrap = Client.Any2EVMMessage({
            messageId: bytes32(uint256(0x1)),
            sourceChainSelector: MUMBAI_SELECTOR,
            sender: abi.encode(address(laneToken)),
            data: _hopData(
                foreignKey,
                uint64(remoteChainId),
                remoteToken,
                originGameId,
                remoteInitiator,
                START_AMOUNT,
                maxHops,
                block.timestamp
            ),
            destTokenAmounts: _tokenAmounts(START_AMOUNT)
        });

        vm.prank(address(mockRouter));
        laneToken.ccipReceive(bootstrap);

        Client.Any2EVMMessage memory collision = Client.Any2EVMMessage({
            messageId: bytes32(uint256(0x2)),
            sourceChainSelector: MUMBAI_SELECTOR,
            sender: abi.encode(address(laneToken)),
            data: _hopData(
                foreignKey,
                uint64(remoteChainId),
                remoteToken,
                originGameId,
                otherInitiator,
                START_AMOUNT,
                maxHops,
                block.timestamp
            ),
            destTokenAmounts: _tokenAmounts(START_AMOUNT)
        });

        vm.prank(address(mockRouter));
        vm.expectRevert(LaneToken.GameMismatch.selector);
        laneToken.ccipReceive(collision);
    }

    function test_deposit_exactAmountRequired() public {
        address depositor = makeAddr("depositor");
        uint256 amount = 5 * 1e6;
        mockUsdc.mint(depositor, amount);

        vm.startPrank(depositor);
        mockUsdc.approve(address(laneToken), amount);
        laneToken.deposit(amount);
        vm.stopPrank();

        assertEq(laneToken.s_balances(depositor), amount);
        assertEq(mockUsdc.balanceOf(address(laneToken)), START_AMOUNT + amount);
    }

    function test_constructor_revertsEmptySupportedChains() public {
        uint256[] memory empty = new uint256[](0);
        vm.expectRevert("no supported chains");
        new LaneToken(
            address(mockRouter),
            address(mockUsdc),
            address(mockVrfCoordinator),
            1,
            bytes32(0),
            block.chainid,
            LOCAL_SELECTOR,
            empty
        );
    }
}
