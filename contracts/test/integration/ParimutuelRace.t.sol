// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulator} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {LaneController} from "../../src/core/LaneController.sol";
import {LaneExecutor} from "../../src/core/LaneExecutor.sol";
import {PrizeCalculator} from "../../src/libraries/PrizeCalculator.sol";
import {ChainConfig} from "../../src/libraries/ChainConfig.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @notice Full parimutuel round over Chainlink Local: two lanes, two CCIP hops each,
///         hops delivered through the simulator router into the LaneExecutor, which
///         records them on the LaneController. First lane to complete wins.
contract ParimutuelRaceTest is Test {
    CCIPLocalSimulator public simulator;
    LaneController public controller;
    LaneExecutor public executor;
    MockERC20 public token;

    address public treasury = makeAddr("treasury");
    address public gasReserve = makeAddr("gasReserve");
    address public cre = makeAddr("cre");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

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
        executor.setHomeConfig(localSelector, localSelector, address(controller), address(executor));
        controller.setHopRecorder(address(executor), true);
        // Single local router: every "remote" executor is this executor.
        executor.setRemoteExecutor(localSelector, address(executor));
        executor.setRemoteExecutor(ChainConfig.SEPOLIA_SELECTOR, address(executor));
        executor.setRemoteExecutor(ChainConfig.ARBITRUM_SEPOLIA_SELECTOR, address(executor));
        executor.setRemoteExecutor(ChainConfig.BASE_SEPOLIA_SELECTOR, address(executor));
        executor.setHopSender(cre, true);

        token.mint(alice, 1000e6);
        token.mint(bob, 1000e6);
        vm.prank(alice);
        token.approve(address(controller), type(uint256).max);
        vm.prank(bob);
        token.approve(address(controller), type(uint256).max);
    }

    function _lanePaths() internal pure returns (uint64[][] memory paths) {
        paths = new uint64[][](2);
        // Lane 0: Sepolia -> Arbitrum Sepolia -> Base Sepolia (2 hops)
        paths[0] = new uint64[](2);
        paths[0][0] = ChainConfig.ARBITRUM_SEPOLIA_SELECTOR;
        paths[0][1] = ChainConfig.BASE_SEPOLIA_SELECTOR;
        // Lane 1: Sepolia -> Base Sepolia -> Arbitrum Sepolia (2 hops)
        paths[1] = new uint64[](2);
        paths[1][0] = ChainConfig.BASE_SEPOLIA_SELECTOR;
        paths[1][1] = ChainConfig.ARBITRUM_SEPOLIA_SELECTOR;
    }

    function test_TwoLaneMultiHopRace_EndToEnd() public {
        // 1. CRE creates the round with two lane circuits.
        vm.prank(cre);
        uint256 roundId = controller.createRound(_lanePaths());

        // 2. Betting window.
        vm.prank(alice);
        controller.buyLaneTokens(roundId, 0, 100e6);
        vm.prank(bob);
        controller.buyLaneTokens(roundId, 1, 300e6);
        assertEq(controller.getTotalPrizePool(roundId), 400e6);

        // 3. Race starts, betting locked.
        vm.prank(cre);
        controller.startRace(roundId);

        // 4. Hops fly via CCIP (simulator delivers synchronously to the executor).
        vm.startPrank(cre);
        executor.sendHop(roundId, 0, ChainConfig.ARBITRUM_SEPOLIA_SELECTOR); // lane 0 hop 1
        executor.sendHop(roundId, 1, ChainConfig.BASE_SEPOLIA_SELECTOR); // lane 1 hop 1

        (, uint8 lane0Hops,,,,) = controller.getLane(roundId, 0);
        (, uint8 lane1Hops,,,,) = controller.getLane(roundId, 1);
        assertEq(lane0Hops, 1);
        assertEq(lane1Hops, 1);

        // Lane 0 completes its circuit first.
        vm.warp(block.timestamp + 60);
        executor.sendHop(roundId, 0, ChainConfig.BASE_SEPOLIA_SELECTOR); // lane 0 hop 2 -> finish
        vm.stopPrank();

        assertEq(controller.getRoundWinner(roundId), 0);
        assertEq(
            uint256(controller.getRoundState(roundId)), uint256(LaneController.RoundState.Finished)
        );

        // Lane 1 finishes later and becomes runner-up.
        vm.warp(block.timestamp + 30);
        vm.prank(cre);
        executor.sendHop(roundId, 1, ChainConfig.ARBITRUM_SEPOLIA_SELECTOR); // lane 1 hop 2 -> finish
        assertEq(controller.getRoundRunnerUp(roundId), 1);

        // 5. Settlement: 70/15/10/5 split.
        vm.prank(cre);
        controller.distributePrizes(roundId);

        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(400e6);
        assertEq(token.balanceOf(treasury), p.platform);
        assertEq(token.balanceOf(gasReserve), p.gasReserve);

        // 6. Bettors claim: alice held the whole winner lane, bob the whole runner-up lane.
        vm.prank(alice);
        assertEq(controller.claimPrize(roundId), p.winner);
        vm.prank(bob);
        assertEq(controller.claimPrize(roundId), p.runnerUp);

        assertEq(token.balanceOf(alice), 1000e6 - 100e6 + p.winner);
        assertEq(token.balanceOf(bob), 1000e6 - 300e6 + p.runnerUp);
    }

    function test_UnauthorizedHopSender_Reverts() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_lanePaths());
        vm.prank(cre);
        controller.startRace(roundId);

        vm.prank(alice);
        vm.expectRevert(LaneExecutor.NotAuthorized.selector);
        executor.sendHop(roundId, 0, ChainConfig.ARBITRUM_SEPOLIA_SELECTOR);
    }

    function test_UnknownDestination_Reverts() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_lanePaths());
        vm.prank(cre);
        controller.startRace(roundId);

        vm.prank(cre);
        vm.expectRevert(abi.encodeWithSelector(LaneExecutor.UnknownDestination.selector, uint64(999)));
        executor.sendHop(roundId, 0, 999);
    }

    function test_ForgedCcipSender_Reverts() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_lanePaths());
        vm.prank(cre);
        controller.startRace(roundId);

        address attacker = makeAddr("attacker");
        Client.Any2EVMMessage memory forged = Client.Any2EVMMessage({
            messageId: keccak256("forged"),
            sourceChainSelector: localSelector,
            sender: abi.encode(attacker),
            data: abi.encode(roundId, uint8(0), ChainConfig.ARBITRUM_SEPOLIA_SELECTOR, block.timestamp),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(sourceRouter));
        vm.expectRevert(
            abi.encodeWithSelector(LaneExecutor.UnauthorizedSource.selector, attacker, address(executor))
        );
        executor.ccipReceive(forged);
    }
}
