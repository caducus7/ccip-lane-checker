// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LaneController} from "../../src/core/LaneController.sol";
import {PrizeCalculator} from "../../src/libraries/PrizeCalculator.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @dev Proves CRE onReport can settle rounds via distributePrizes / sweepUnclaimed reports.
contract OnReportSettlementTest is Test {
    LaneController public controller;
    MockERC20 public token;

    address public treasury = makeAddr("treasury");
    address public gasReserve = makeAddr("gasReserve");
    address public cre = makeAddr("cre");
    address public player = makeAddr("player");
    address public rival = makeAddr("rival");
    address public executor = makeAddr("executor");

    uint64 constant SEPOLIA = 16015286601757825753;
    uint64 constant ARBITRUM = 3478487238524512106;

    function setUp() public {
        vm.warp(1_000_000);
        token = new MockERC20("USDC", "USDC", 6);
        controller = new LaneController(address(this), address(token), treasury, gasReserve, cre);
        controller.setHopRecorder(executor, true);

        token.mint(player, 1_000_000e6);
        token.mint(rival, 1_000_000e6);
        vm.prank(player);
        token.approve(address(controller), type(uint256).max);
        vm.prank(rival);
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

    function _createRound() internal returns (uint256 roundId) {
        vm.prank(cre);
        roundId = controller.createRound(_twoLanePaths());
    }

    function _finishLane(uint256 roundId, uint8 laneId) internal {
        (uint64[] memory path,,,,,) = controller.getLane(roundId, laneId);
        vm.startPrank(executor);
        controller.recordHop(roundId, laneId, path[0], block.timestamp - 120);
        controller.recordHop(roundId, laneId, path[1], block.timestamp - 90);
        vm.stopPrank();
    }

    function _settleRound(uint256 roundId) internal {
        vm.prank(player);
        controller.buyLaneTokens(roundId, 0, 100e6);
        vm.prank(rival);
        controller.buyLaneTokens(roundId, 1, 300e6);

        vm.prank(cre);
        controller.startRace(roundId);
        _finishLane(roundId, 0);
        _finishLane(roundId, 1);
    }

    function test_onReport_distributePrizes_succeeds() public {
        uint256 roundId = _createRound();
        _settleRound(roundId);

        bytes memory report = abi.encodeWithSelector(LaneController.distributePrizes.selector, roundId);
        vm.prank(cre);
        controller.onReport("", report);

        assertEq(uint256(controller.getRoundState(roundId)), uint256(LaneController.RoundState.Settled));

        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(400e6);
        assertEq(token.balanceOf(treasury), p.platform);
        assertEq(token.balanceOf(gasReserve), p.gasReserve);
    }

    function test_onReport_sweepUnclaimed_succeeds() public {
        uint256 roundId = _createRound();
        _settleRound(roundId);

        bytes memory distributeReport = abi.encodeWithSelector(LaneController.distributePrizes.selector, roundId);
        vm.prank(cre);
        controller.onReport("", distributeReport);

        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(400e6);
        uint256 treasuryBefore = token.balanceOf(treasury);

        vm.warp(block.timestamp + controller.claimWindow() + 1);

        bytes memory sweepReport = abi.encodeWithSelector(LaneController.sweepUnclaimed.selector, roundId);
        vm.prank(cre);
        controller.onReport("", sweepReport);

        assertEq(token.balanceOf(treasury), treasuryBefore + p.winner + p.runnerUp);
    }
}
