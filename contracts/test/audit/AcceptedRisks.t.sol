// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {LaneController} from "../../src/core/LaneController.sol";
import {LaneExecutor} from "../../src/core/LaneExecutor.sol";
import {LaneToken} from "../../src/core/LaneToken.sol";
import {MockCCIPRouter} from "../../src/mocks/MockCCIPRouter.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockVRFCoordinatorV2Plus} from "../../src/mocks/MockVRFCoordinatorV2Plus.sol";

/// @notice Regression tests for accepted-risk mitigations.
contract AcceptedRisksTest is Test {
    MockCCIPRouter public router;
    LaneExecutor public executor;
    LaneController public controller;
    LaneToken public laneToken;
    MockERC20 public token;

    address public treasury = makeAddr("treasury");
    address public gasReserve = makeAddr("gasReserve");
    address public cre = makeAddr("cre");
    address public player = makeAddr("player");

    uint64 constant LOCAL_SELECTOR = 111;
    uint64 constant REMOTE_SELECTOR = 222;
    uint64 constant HOP_CHAIN = 333;

    function setUp() public {
        vm.warp(1_000_000);
        router = new MockCCIPRouter();
        executor = new LaneExecutor(address(router), address(this));
        token = new MockERC20("USDC", "USDC", 6);
        controller = new LaneController(address(this), address(token), treasury, gasReserve, cre);

        executor.setHomeConfig(LOCAL_SELECTOR, LOCAL_SELECTOR, address(controller), address(executor));
        assertEq(executor.laneController(), address(controller));
        controller.setHopRecorder(address(executor), true);
        executor.setRemoteExecutor(HOP_CHAIN, address(executor));
        executor.setRemoteExecutor(REMOTE_SELECTOR, address(executor));
        executor.setHopSender(cre, true);

        MockVRFCoordinatorV2Plus vrf = new MockVRFCoordinatorV2Plus();
        uint256[] memory chains = new uint256[](1);
        chains[0] = LOCAL_SELECTOR;
        laneToken = new LaneToken(
            address(router), address(token), address(vrf), 1, bytes32(0), block.chainid, LOCAL_SELECTOR, chains
        );
        laneToken.setRemoteLaneToken(LOCAL_SELECTOR, address(laneToken));

        token.mint(player, 100e6);
        vm.prank(player);
        token.approve(address(laneToken), type(uint256).max);
        vm.prank(player);
        laneToken.deposit(100e6);
    }

    function _lanePaths() internal pure returns (uint64[][] memory paths) {
        paths = new uint64[][](2);
        paths[0] = new uint64[](1);
        paths[0][0] = HOP_CHAIN;
        paths[1] = new uint64[](1);
        paths[1][0] = HOP_CHAIN;
    }

    function test_executorPause_blocksSendHop() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_lanePaths());
        vm.prank(cre);
        controller.startRace(roundId);

        executor.pause();
        vm.prank(cre);
        vm.expectRevert();
        executor.sendHop(roundId, 0, HOP_CHAIN);
    }

    function test_homeControllerPause_blocksHopReceive() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_lanePaths());
        vm.prank(cre);
        controller.startRace(roundId);

        controller.pause();

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256("hop"),
            sourceChainSelector: REMOTE_SELECTOR,
            sender: abi.encode(address(executor)),
            data: abi.encode(roundId, uint8(0), HOP_CHAIN, block.timestamp),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(router));
        vm.expectRevert(LaneExecutor.HomeControllerPaused.selector);
        executor.ccipReceive(message);
    }

    function test_setLaneController_mismatchAfterHomeConfig_reverts() public {
        address other = makeAddr("otherController");
        vm.expectRevert(LaneExecutor.ControllerMismatch.selector);
        executor.setLaneController(other);
    }

    function test_sendHop_insufficientCcipFee_reverts() public {
        router.setMockFee(1 ether);
        vm.deal(address(executor), 0);

        vm.prank(cre);
        uint256 roundId = controller.createRound(_lanePaths());
        vm.prank(cre);
        controller.startRace(roundId);

        vm.prank(cre);
        vm.expectRevert(abi.encodeWithSelector(LaneExecutor.InsufficientCcipFee.selector, 1 ether, uint256(0)));
        executor.sendHop(roundId, 0, HOP_CHAIN);
    }

    function test_startGame_rejectsZeroMaxHops() public {
        vm.prank(player);
        vm.expectRevert(LaneToken.InvalidMaxHops.selector);
        laneToken.startGame(LOCAL_SELECTOR, 10e6, 0);
    }

    function test_startGame_rejectsExcessiveMaxHops() public {
        uint8 excessive = laneToken.MAX_HOPS() + 1;
        vm.prank(player);
        vm.expectRevert(LaneToken.InvalidMaxHops.selector);
        laneToken.startGame(LOCAL_SELECTOR, 10e6, excessive);
    }

    function test_abandonGame_refundsAfterTimeout() public {
        vm.deal(address(laneToken), 1 ether);
        vm.prank(player);
        laneToken.startGame(LOCAL_SELECTOR, 10e6, 2);

        vm.warp(block.timestamp + laneToken.GAME_ABANDON_TIMEOUT() + 1);
        vm.prank(player);
        laneToken.abandonGame(1);

        assertEq(laneToken.s_balances(player), 100e6);
        assertEq(laneToken.s_tokensInPlay(), 0);
        (,,,,,, bool active) = laneToken.getGameRound(1);
        assertFalse(active);
    }

    function test_abandonGame_beforeTimeout_reverts() public {
        vm.deal(address(laneToken), 1 ether);
        vm.prank(player);
        laneToken.startGame(LOCAL_SELECTOR, 10e6, 2);

        vm.prank(player);
        vm.expectRevert(LaneToken.GameNotAbandonable.selector);
        laneToken.abandonGame(1);
    }

    function test_startGame_insufficientCcipFee_reverts() public {
        router.setMockFee(1 ether);
        vm.deal(address(laneToken), 0);

        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(LaneToken.InsufficientCcipFee.selector, 1 ether, uint256(0)));
        laneToken.startGame(LOCAL_SELECTOR, 10e6, 1);
    }
}
