// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {LaneController} from "../../src/core/LaneController.sol";
import {LaneExecutor} from "../../src/core/LaneExecutor.sol";
import {LaneToken} from "../../src/core/LaneToken.sol";
import {PrizeCalculator} from "../../src/libraries/PrizeCalculator.sol";
import {MockCCIPRouter} from "../../src/mocks/MockCCIPRouter.sol";
import {MockDeliveringCCIPRouter} from "../../src/mocks/MockDeliveringCCIPRouter.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockVRFCoordinatorV2Plus} from "../../src/mocks/MockVRFCoordinatorV2Plus.sol";

/// @notice Regression tests for fourth-pass audit finding and promoted leads.
contract FourthPassFixesTest is Test {
    uint64 constant ORIGIN_SELECTOR = 111;
    uint64 constant REMOTE_SELECTOR = 222;
    uint64 constant HOP_CHAIN = 333;

    uint256 constant STAKE = 10e6;

    function test_vrfReturnHop_reactivatesBridgedOutOriginGame() public {
        vm.warp(1_000_000);
        MockDeliveringCCIPRouter router = new MockDeliveringCCIPRouter();
        MockERC20 token = new MockERC20("USDC", "USDC", 6);
        MockVRFCoordinatorV2Plus vrf = new MockVRFCoordinatorV2Plus();
        address player = makeAddr("player");

        uint256[] memory originChains = new uint256[](2);
        originChains[0] = REMOTE_SELECTOR;
        originChains[1] = ORIGIN_SELECTOR;
        LaneToken origin = new LaneToken(
            address(router), address(token), address(vrf), 1, bytes32(0), 1, ORIGIN_SELECTOR, originChains
        );

        uint256[] memory remoteChains = new uint256[](2);
        remoteChains[0] = ORIGIN_SELECTOR;
        remoteChains[1] = REMOTE_SELECTOR;
        LaneToken remote = new LaneToken(
            address(router), address(token), address(vrf), 1, bytes32(0), 2, REMOTE_SELECTOR, remoteChains
        );

        origin.setRemoteLaneToken(REMOTE_SELECTOR, address(remote));
        remote.setRemoteLaneToken(ORIGIN_SELECTOR, address(origin));
        router.setChainSelector(address(origin), ORIGIN_SELECTOR);
        router.setChainSelector(address(remote), REMOTE_SELECTOR);
        vm.deal(address(origin), 1 ether);
        vm.deal(address(remote), 1 ether);

        token.mint(player, STAKE);
        vm.startPrank(player);
        token.approve(address(origin), type(uint256).max);
        origin.deposit(STAKE);
        origin.startGame(REMOTE_SELECTOR, STAKE, 3);
        vm.stopPrank();

        assertEq(origin.s_tokensInPlay(), 0);
        (,,, uint8 remoteHops,,, bool remoteActive) = remote.getGameRound(1);
        assertEq(remoteHops, 1);
        assertTrue(remoteActive);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 0;
        vrf.fulfillRandomWords(1, address(remote), randomWords);

        (,,, uint8 originHops,,, bool originActive) = origin.getGameRound(1);
        assertEq(originHops, 1);
        assertTrue(originActive);
        assertEq(origin.s_tokensInPlay(), STAKE);
    }

    function test_executorCcipReceive_duplicateMessageId_reverts() public {
        vm.warp(1_000_000);
        MockCCIPRouter router = new MockCCIPRouter();
        LaneExecutor executor = new LaneExecutor(address(router), address(this));
        MockCanonicalController mockCanonical = new MockCanonicalController();

        executor.setHomeConfig(ORIGIN_SELECTOR, ORIGIN_SELECTOR, address(mockCanonical), address(executor));
        executor.setRemoteExecutor(REMOTE_SELECTOR, address(executor));

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256("dup-hop"),
            sourceChainSelector: REMOTE_SELECTOR,
            sender: abi.encode(address(executor)),
            data: abi.encode(uint256(1), uint8(0), REMOTE_SELECTOR, block.timestamp),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(router));
        executor.ccipReceive(message);

        vm.prank(address(router));
        vm.expectRevert(abi.encodeWithSelector(LaneExecutor.DuplicateMessage.selector, keccak256("dup-hop")));
        executor.ccipReceive(message);
    }

    function test_startGame_rejectsUnwiredDestination() public {
        vm.warp(1_000_000);
        MockCCIPRouter router = new MockCCIPRouter();
        MockERC20 token = new MockERC20("USDC", "USDC", 6);
        MockVRFCoordinatorV2Plus vrf = new MockVRFCoordinatorV2Plus();
        address player = makeAddr("player");

        uint256[] memory chains = new uint256[](1);
        chains[0] = ORIGIN_SELECTOR;
        LaneToken laneToken = new LaneToken(
            address(router), address(token), address(vrf), 1, bytes32(0), 1, ORIGIN_SELECTOR, chains
        );

        token.mint(player, STAKE);
        vm.startPrank(player);
        token.approve(address(laneToken), type(uint256).max);
        laneToken.deposit(STAKE);
        vm.expectRevert(abi.encodeWithSelector(LaneToken.UnwiredRemoteLaneToken.selector, REMOTE_SELECTOR));
        laneToken.startGame(REMOTE_SELECTOR, STAKE, 1);
        vm.stopPrank();
    }

    function test_sweepUsesSnapshottedClaimWindow() public {
        vm.warp(1_000_000);
        MockERC20 token = new MockERC20("USDC", "USDC", 6);
        LaneController controller =
            new LaneController(address(this), address(token), makeAddr("treasury"), makeAddr("gas"), makeAddr("cre"));
        address cre = controller.creForwarder();
        address executor = makeAddr("executor");
        controller.setHopRecorder(executor, true);

        address player = makeAddr("player");
        address rival = makeAddr("rival");
        token.mint(player, 100e6);
        token.mint(rival, 100e6);
        vm.prank(player);
        token.approve(address(controller), type(uint256).max);
        vm.prank(rival);
        token.approve(address(controller), type(uint256).max);

        uint64[][] memory paths = new uint64[][](2);
        paths[0] = new uint64[](1);
        paths[0][0] = HOP_CHAIN;
        paths[1] = new uint64[](1);
        paths[1][0] = HOP_CHAIN;

        vm.prank(cre);
        uint256 roundId = controller.createRound(paths);
        vm.prank(player);
        controller.buyLaneTokens(roundId, 0, 100e6);
        vm.prank(rival);
        controller.buyLaneTokens(roundId, 1, 100e6);
        vm.prank(cre);
        controller.startRace(roundId);

        vm.startPrank(executor);
        controller.recordHop(roundId, 0, HOP_CHAIN, block.timestamp);
        controller.recordHop(roundId, 1, HOP_CHAIN, block.timestamp + 1);
        vm.stopPrank();

        vm.prank(cre);
        controller.distributePrizes(roundId);

        // Live claimWindow changes must not shorten the snapshotted window.
        controller.setClaimWindow(1);
        vm.prank(cre);
        vm.expectRevert(LaneController.ClaimWindowActive.selector);
        controller.sweepUnclaimed(roundId);
    }

    function test_runnerUpTimeout_snapshottedAtWinnerDeclaration() public {
        vm.warp(1_000_000);
        MockERC20 token = new MockERC20("USDC", "USDC", 6);
        LaneController controller =
            new LaneController(address(this), address(token), makeAddr("treasury"), makeAddr("gas"), makeAddr("cre"));
        address cre = controller.creForwarder();
        address executor = makeAddr("executor");
        controller.setHopRecorder(executor, true);

        address player = makeAddr("player");
        token.mint(player, 100e6);
        vm.prank(player);
        token.approve(address(controller), type(uint256).max);

        uint64[][] memory paths = new uint64[][](2);
        paths[0] = new uint64[](1);
        paths[0][0] = HOP_CHAIN;
        paths[1] = new uint64[](1);
        paths[1][0] = HOP_CHAIN;

        vm.prank(cre);
        uint256 roundId = controller.createRound(paths);
        vm.prank(player);
        controller.buyLaneTokens(roundId, 0, 100e6);
        vm.prank(cre);
        controller.startRace(roundId);

        vm.prank(executor);
        controller.recordHop(roundId, 0, HOP_CHAIN, block.timestamp);

        controller.setRunnerUpSettlementTimeout(0);

        vm.prank(cre);
        vm.expectRevert(LaneController.RunnerUpPending.selector);
        controller.distributePrizes(roundId);
    }
}

contract MockCanonicalController {
    function paused() external pure returns (bool) {
        return false;
    }

    function recordHop(uint256, uint8, uint64, uint256) external {}
}
