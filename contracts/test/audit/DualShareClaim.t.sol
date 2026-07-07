// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LaneController} from "../../src/core/LaneController.sol";
import {PrizeCalculator} from "../../src/libraries/PrizeCalculator.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @notice Audit finding 2: empty-winner redirect must not orphan runner-up share on same lane.
contract DualShareClaimTest is Test {
    LaneController public controller;
    MockERC20 public token;

    address public treasury = makeAddr("treasury");
    address public gasReserve = makeAddr("gasReserve");
    address public cre = makeAddr("cre");
    address public player = makeAddr("player");
    address public executor = makeAddr("executor");

    uint64 constant SEPOLIA = 16015286601757825753;
    uint64 constant ARBITRUM = 3478487238524512106;

    function setUp() public {
        vm.warp(1_000_000);
        token = new MockERC20("USDC", "USDC", 6);
        controller = new LaneController(address(this), address(token), treasury, gasReserve, cre);
        controller.setHopRecorder(executor, true);

        token.mint(player, 1_000_000e6);
        vm.prank(player);
        token.approve(address(controller), type(uint256).max);
    }

    function _twoLanePaths() internal pure returns (uint64[][] memory paths) {
        paths = new uint64[][](2);
        paths[0] = new uint64[](2);
        paths[0][0] = SEPOLIA;
        paths[0][1] = ARBITRUM;
        paths[1] = new uint64[](2);
        paths[1][0] = ARBITRUM;
        paths[1][1] = SEPOLIA;
    }

    function _finishLane(uint256 roundId, uint8 laneId) internal {
        (uint64[] memory path,,,,,) = controller.getLane(roundId, laneId);
        vm.startPrank(executor);
        controller.recordHop(roundId, laneId, path[0], block.timestamp - 120);
        controller.recordHop(roundId, laneId, path[1], block.timestamp - 90);
        vm.stopPrank();
    }

    function _setupEmptyWinnerRound() internal returns (uint256 roundId) {
        vm.prank(cre);
        roundId = controller.createRound(_twoLanePaths());

        vm.prank(player);
        controller.buyLaneTokens(roundId, 1, 200e6);

        vm.prank(cre);
        controller.startRace(roundId);
        _finishLane(roundId, 0);
        _finishLane(roundId, 1);

        vm.prank(cre);
        controller.distributePrizes(roundId);
    }

    function test_emptyWinner_bettorClaimsWinnerAndRunnerUp() public {
        uint256 roundId = _setupEmptyWinnerRound();
        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(200e6);

        vm.prank(player);
        uint256 claimed = controller.claimPrize(roundId);

        assertEq(claimed, p.winner + p.runnerUp, "bettor must receive winner + runner-up on same lane");
        assertEq(claimed, 150e6);
    }

    function test_emptyWinner_runnerUpNotSweptToTreasury() public {
        uint256 roundId = _setupEmptyWinnerRound();
        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(200e6);

        uint256 treasuryAfterDistribute = token.balanceOf(treasury);
        assertEq(treasuryAfterDistribute, p.platform);

        vm.prank(player);
        controller.claimPrize(roundId);

        assertEq(token.balanceOf(treasury), treasuryAfterDistribute, "treasury must not absorb runner-up share");

        vm.warp(block.timestamp + controller.claimWindow() + 1);
        vm.prank(cre);
        vm.expectRevert(LaneController.NothingToClaim.selector);
        controller.sweepUnclaimed(roundId);
    }
}
