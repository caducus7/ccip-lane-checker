// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulator} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {BurnMintERC677Helper} from "@chainlink/local/src/ccip/BurnMintERC677Helper.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {LaneToken} from "../../src/core/LaneToken.sol";
import {LaneController} from "../../src/core/LaneController.sol";
import {LaneExecutor} from "../../src/core/LaneExecutor.sol";
import {PrizeCalculator} from "../../src/libraries/PrizeCalculator.sol";
import {ChainConfig} from "../../src/libraries/ChainConfig.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockVRFCoordinatorV2Plus} from "../../src/mocks/MockVRFCoordinatorV2Plus.sol";

/// @notice End-to-end solo-mode smoke over Chainlink Local's CCIPLocalSimulator:
///         deposit -> startGame -> 3 CCIP hops (2 VRF-driven) -> withdraw, with
///         balance conservation checked at every stage.
contract FullSmokeSoloTest is Test {
    CCIPLocalSimulator public simulator;
    LaneToken public laneToken;
    BurnMintERC677Helper public ccipBnM;
    MockVRFCoordinatorV2Plus public vrfCoordinator;

    address public player = makeAddr("player");
    uint64 public chainSelector;
    IRouterClient public sourceRouter;

    uint256 constant START_AMOUNT = 1e18;

    event GameFinished(uint256 indexed gameId, uint256 totalLatency, uint8 totalHops);
    event Withdrawn(address indexed user, uint256 amount);

    function setUp() public {
        simulator = new CCIPLocalSimulator();
        (uint64 chainSelector_, IRouterClient router,,,, BurnMintERC677Helper ccipBnM_,) =
            simulator.configuration();
        chainSelector = chainSelector_;
        sourceRouter = router;
        ccipBnM = ccipBnM_;

        vrfCoordinator = new MockVRFCoordinatorV2Plus();

        uint256[] memory supportedChains = new uint256[](1);
        supportedChains[0] = chainSelector;

        laneToken = new LaneToken(
            address(sourceRouter),
            address(ccipBnM),
            address(vrfCoordinator),
            1,
            bytes32(0),
            supportedChains
        );
        laneToken.setRemoteLaneToken(chainSelector, address(laneToken));

        ccipBnM.drip(player);
    }

    /// @dev Fulfills the pending VRF request, which makes LaneToken bridge the next hop;
    ///      the simulator delivers it synchronously so the hop lands in the same call.
    function _fulfillNextHop(uint256 requestId, uint256 randomWord) internal {
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = randomWord;
        vrfCoordinator.fulfillRandomWords(requestId, address(laneToken), randomWords);
    }

    function test_FullSoloLifecycle_DepositMultiHopVrfWithdraw() public {
        // 1. Deposit underlying into the game balance.
        vm.startPrank(player);
        ccipBnM.approve(address(laneToken), START_AMOUNT);
        laneToken.deposit(START_AMOUNT);
        vm.stopPrank();

        assertEq(laneToken.s_balances(player), START_AMOUNT);
        assertEq(ccipBnM.balanceOf(player), 0);
        assertEq(ccipBnM.balanceOf(address(laneToken)), START_AMOUNT);

        // 2. Start a 3-hop game. Hop 1 is delivered synchronously by the simulator,
        //    then LaneToken asks VRF for the next lane.
        vm.prank(player);
        laneToken.startGame(chainSelector, START_AMOUNT, 3);

        (,,, uint8 hopsCompleted,,, bool isActive) = laneToken.getGameRound(1);
        assertEq(hopsCompleted, 1);
        assertTrue(isActive);
        assertEq(laneToken.s_balances(player), 0);
        assertEq(vrfCoordinator.lastRequestId(), 1);

        // 3. Hop 2 via VRF fulfillment.
        vm.warp(block.timestamp + 120);
        _fulfillNextHop(1, 42);

        (,,, hopsCompleted,,, isActive) = laneToken.getGameRound(1);
        assertEq(hopsCompleted, 2);
        assertTrue(isActive);
        assertEq(vrfCoordinator.lastRequestId(), 2);

        // 4. Hop 3 via VRF fulfillment: game finishes, stake credited back to player.
        vm.warp(block.timestamp + 120);
        vm.expectEmit(true, false, false, true);
        emit GameFinished(1, 0, 3); // simulator delivers in-tx, so per-hop latency is 0
        _fulfillNextHop(2, 1337);

        (,,, hopsCompleted,,, isActive) = laneToken.getGameRound(1);
        assertEq(hopsCompleted, 3);
        assertFalse(isActive);
        assertEq(laneToken.s_balances(player), START_AMOUNT);

        // Tokens never left the contract (single local router loops back).
        assertEq(ccipBnM.balanceOf(address(laneToken)), START_AMOUNT);

        // 5. Withdraw everything back to the wallet.
        vm.prank(player);
        vm.expectEmit(true, false, false, true);
        emit Withdrawn(player, START_AMOUNT);
        laneToken.withdraw(START_AMOUNT);

        assertEq(ccipBnM.balanceOf(player), START_AMOUNT);
        assertEq(ccipBnM.balanceOf(address(laneToken)), 0);
        assertEq(laneToken.s_balances(player), 0);
    }

    function test_FullSoloLifecycle_BackToBackGames() public {
        vm.startPrank(player);
        ccipBnM.approve(address(laneToken), START_AMOUNT);
        laneToken.deposit(START_AMOUNT);

        // Game 1: single hop, finishes immediately.
        laneToken.startGame(chainSelector, START_AMOUNT, 1);
        vm.stopPrank();
        (,,,,,, bool isActive) = laneToken.getGameRound(1);
        assertFalse(isActive);
        assertEq(laneToken.s_balances(player), START_AMOUNT);

        // Game 2 reuses the returned stake: 2 hops, needs one VRF fulfillment.
        vm.prank(player);
        laneToken.startGame(chainSelector, START_AMOUNT, 2);
        _fulfillNextHop(1, 7);

        (,,, uint8 hopsCompleted,,, bool active2) = laneToken.getGameRound(2);
        assertEq(hopsCompleted, 2);
        assertFalse(active2);
        assertEq(laneToken.s_balances(player), START_AMOUNT);

        vm.prank(player);
        laneToken.withdraw(START_AMOUNT);
        assertEq(ccipBnM.balanceOf(player), START_AMOUNT);
    }
}

/// @notice End-to-end parimutuel smoke over Chainlink Local: createRound -> bets on
///         both lanes -> startRace -> every hop delivered through executor.sendHop and
///         the simulator router -> distributePrizes -> both bettors claim. Includes an
///         exact settlement-conservation assertion (no tokens minted or lost).
contract FullSmokeParimutuelTest is Test {
    CCIPLocalSimulator public simulator;
    LaneController public controller;
    LaneExecutor public executor;
    MockERC20 public token;

    address public treasury = makeAddr("treasury");
    address public gasReserve = makeAddr("gasReserve");
    address public cre = makeAddr("cre");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");

    uint64 public localSelector;
    IRouterClient public sourceRouter;

    function setUp() public {
        // Realistic timestamp so the round-creation cooldown window is in the past.
        vm.warp(1_000_000);
        simulator = new CCIPLocalSimulator();
        (uint64 chainSelector, IRouterClient router,,,,,) = simulator.configuration();
        localSelector = chainSelector;
        sourceRouter = router;

        token = new MockERC20("USDC", "USDC", 6);
        controller = new LaneController(address(this), address(token), treasury, gasReserve, cre);
        executor = new LaneExecutor(address(sourceRouter), address(this));

        executor.setLaneController(address(controller));
        controller.setHopRecorder(address(executor), true);
        // Single local router: every "remote" executor is this executor.
        executor.setRemoteExecutor(localSelector, address(executor));
        executor.setRemoteExecutor(ChainConfig.SEPOLIA_SELECTOR, address(executor));
        executor.setRemoteExecutor(ChainConfig.ARBITRUM_SEPOLIA_SELECTOR, address(executor));
        executor.setRemoteExecutor(ChainConfig.BASE_SEPOLIA_SELECTOR, address(executor));
        executor.setHopSender(cre, true);

        address[3] memory bettors = [alice, bob, carol];
        for (uint256 i = 0; i < bettors.length; i++) {
            token.mint(bettors[i], 1000e6);
            vm.prank(bettors[i]);
            token.approve(address(controller), type(uint256).max);
        }
    }

    /// @dev Two lanes, three hops each, opposite circuits through the testnet selectors.
    function _threeHopLanePaths() internal pure returns (uint64[][] memory paths) {
        paths = new uint64[][](2);
        paths[0] = new uint64[](3);
        paths[0][0] = ChainConfig.ARBITRUM_SEPOLIA_SELECTOR;
        paths[0][1] = ChainConfig.BASE_SEPOLIA_SELECTOR;
        paths[0][2] = ChainConfig.SEPOLIA_SELECTOR;
        paths[1] = new uint64[](3);
        paths[1][0] = ChainConfig.BASE_SEPOLIA_SELECTOR;
        paths[1][1] = ChainConfig.ARBITRUM_SEPOLIA_SELECTOR;
        paths[1][2] = ChainConfig.SEPOLIA_SELECTOR;
    }

    /// @dev Drives every remaining hop of a lane through executor.sendHop; the local
    ///      simulator delivers each CCIP message synchronously into the executor.
    function _runLaneToCompletion(uint256 roundId, uint8 laneId) internal {
        (uint64[] memory path, uint8 done, uint8 required,,,) = controller.getLane(roundId, laneId);
        vm.startPrank(cre);
        for (uint8 hop = done; hop < required; hop++) {
            vm.warp(block.timestamp + 30);
            executor.sendHop(roundId, laneId, path[hop]);
        }
        vm.stopPrank();
    }

    function test_FullParimutuelLifecycle_ThreeHopRace() public {
        // 1. CRE creates the round.
        vm.prank(cre);
        uint256 roundId = controller.createRound(_threeHopLanePaths());
        assertEq(
            uint256(controller.getRoundState(roundId)), uint256(LaneController.RoundState.Betting)
        );

        // 2. Bets land on both lanes.
        vm.prank(alice);
        controller.buyLaneTokens(roundId, 0, 100e6);
        vm.prank(bob);
        controller.buyLaneTokens(roundId, 1, 300e6);
        assertEq(controller.getTotalPrizePool(roundId), 400e6);
        assertEq(token.balanceOf(address(controller)), 400e6);

        // 3. Race starts; betting is locked.
        vm.prank(cre);
        controller.startRace(roundId);
        vm.prank(alice);
        vm.expectRevert(LaneController.BettingClosed.selector);
        controller.buyLaneTokens(roundId, 0, 1e6);

        // 4. Interleave the first hop of each lane, then race lane 0 to the finish.
        vm.startPrank(cre);
        executor.sendHop(roundId, 0, ChainConfig.ARBITRUM_SEPOLIA_SELECTOR);
        executor.sendHop(roundId, 1, ChainConfig.BASE_SEPOLIA_SELECTOR);
        vm.stopPrank();

        (, uint8 lane0Hops,,,,) = controller.getLane(roundId, 0);
        (, uint8 lane1Hops,,,,) = controller.getLane(roundId, 1);
        assertEq(lane0Hops, 1);
        assertEq(lane1Hops, 1);

        _runLaneToCompletion(roundId, 0);
        assertEq(controller.getRoundWinner(roundId), 0);
        assertEq(
            uint256(controller.getRoundState(roundId)), uint256(LaneController.RoundState.Finished)
        );

        // Runner-up lane still completes its circuit after the winner is declared.
        _runLaneToCompletion(roundId, 1);
        assertEq(controller.getRoundRunnerUp(roundId), 1);

        // 5. Settlement: 70/15/10/5 split.
        vm.prank(cre);
        controller.distributePrizes(roundId);
        assertEq(
            uint256(controller.getRoundState(roundId)), uint256(LaneController.RoundState.Settled)
        );

        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(400e6);
        assertEq(token.balanceOf(treasury), p.platform);
        assertEq(token.balanceOf(gasReserve), p.gasReserve);

        // 6. Both bettors claim: sole bettors on their lanes get the full lane shares.
        vm.prank(alice);
        assertEq(controller.claimPrize(roundId), p.winner);
        vm.prank(bob);
        assertEq(controller.claimPrize(roundId), p.runnerUp);

        assertEq(token.balanceOf(alice), 1000e6 - 100e6 + p.winner);
        assertEq(token.balanceOf(bob), 1000e6 - 300e6 + p.runnerUp);
        assertEq(token.balanceOf(address(controller)), 0);
    }

    /// @notice Exact conservation across the full CCIP-driven settlement path:
    ///         pool == treasury + gasReserve + all claims + residual dust, and the
    ///         controller is fully drained after the dust sweep.
    function test_Settlement_Conservation_ProRataWithDust() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_threeHopLanePaths());

        // Amounts chosen so pro-rata winner claims leave rounding dust behind.
        vm.prank(alice);
        controller.buyLaneTokens(roundId, 0, 100e6);
        vm.prank(carol);
        controller.buyLaneTokens(roundId, 0, 33e6);
        vm.prank(bob);
        controller.buyLaneTokens(roundId, 1, 300e6);

        uint256 pool = controller.getTotalPrizePool(roundId);
        assertEq(pool, 433e6);
        assertEq(token.balanceOf(address(controller)), pool);

        vm.prank(cre);
        controller.startRace(roundId);

        _runLaneToCompletion(roundId, 0); // lane 0 wins
        _runLaneToCompletion(roundId, 1); // lane 1 runner-up

        vm.prank(cre);
        controller.distributePrizes(roundId);

        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(pool);
        // Shares sum exactly to the pool by construction.
        assertEq(p.winner + p.platform + p.gasReserve + p.runnerUp, pool);
        // Claimable shares stay escrowed in the controller until claimed.
        assertEq(token.balanceOf(address(controller)), p.winner + p.runnerUp);

        vm.prank(alice);
        uint256 aliceClaim = controller.claimPrize(roundId);
        vm.prank(carol);
        uint256 carolClaim = controller.claimPrize(roundId);
        vm.prank(bob);
        uint256 bobClaim = controller.claimPrize(roundId);

        // Pro-rata winner split (floor division).
        assertEq(aliceClaim, (p.winner * 100e6) / 133e6);
        assertEq(carolClaim, (p.winner * 33e6) / 133e6);
        // Sole runner-up bettor takes the full runner-up share.
        assertEq(bobClaim, p.runnerUp);

        // Conservation: every unit of the pool is accounted for.
        uint256 residual = token.balanceOf(address(controller));
        assertEq(
            token.balanceOf(treasury) + token.balanceOf(gasReserve) + aliceClaim + carolClaim
                + bobClaim + residual,
            pool
        );
        assertEq(residual, p.winner - aliceClaim - carolClaim);

        // Sweep rounding dust to the platform; controller ends fully drained.
        if (residual > 0) {
            uint256 treasuryBefore = token.balanceOf(treasury);
            controller.sweepUnclaimed(roundId);
            assertEq(token.balanceOf(treasury), treasuryBefore + residual);
        }
        assertEq(token.balanceOf(address(controller)), 0);

        // Nothing left to claim for anyone.
        vm.prank(alice);
        vm.expectRevert(LaneController.NothingToClaim.selector);
        controller.claimPrize(roundId);
    }
}
