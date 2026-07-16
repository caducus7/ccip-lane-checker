// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LaneController} from "../../src/core/LaneController.sol";
import {LaneExecutor} from "../../src/core/LaneExecutor.sol";
import {CreReportAuth} from "../../src/libraries/CreReportAuth.sol";
import {MockCCIPRouter} from "../../src/mocks/MockCCIPRouter.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @notice Residual audit fixes: stuck-race refunds + Keystone metadata allowlists.
contract ResidualFixesTest is Test {
    LaneController public controller;
    MockERC20 public token;

    address public treasury = makeAddr("treasury");
    address public gasReserve = makeAddr("gasReserve");
    address public cre = makeAddr("cre");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public executor = makeAddr("executor");

    uint64 constant SEPOLIA = 16015286601757825753;
    uint64 constant ARBITRUM = 3478487238524512106;

    bytes32 constant WORKFLOW_ID = keccak256("lane-round-scheduler");
    bytes10 constant WORKFLOW_NAME = bytes10("roundSched");
    address constant WORKFLOW_OWNER = address(0xBEEF);

    function setUp() public {
        vm.warp(1_000_000);
        token = new MockERC20("USDC", "USDC", 6);
        controller = new LaneController(address(this), address(token), treasury, gasReserve, cre);
        controller.setHopRecorder(executor, true);

        token.mint(alice, 1_000_000e6);
        token.mint(bob, 1_000_000e6);
        vm.prank(alice);
        token.approve(address(controller), type(uint256).max);
        vm.prank(bob);
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

    function _metadata(bytes32 id, bytes10 name, address owner) internal pure returns (bytes memory) {
        return abi.encodePacked(id, name, owner, bytes2(0));
    }

    function test_abortRacingRound_afterTimeout_refundsBettors() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_twoLanePaths());

        vm.prank(alice);
        controller.buyLaneTokens(roundId, 0, 100e6);
        vm.prank(bob);
        controller.buyLaneTokens(roundId, 1, 50e6);

        vm.prank(cre);
        controller.startRace(roundId);

        vm.prank(alice);
        vm.expectRevert(LaneController.RaceNotAbortable.selector);
        controller.abortRace(roundId);

        vm.warp(block.timestamp + controller.raceAbandonTimeout() + 1);
        // Permissionless after timeout.
        controller.abortRace(roundId);
        assertEq(
            uint256(controller.getRoundState(roundId)), uint256(LaneController.RoundState.Aborted)
        );

        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        assertEq(controller.claimRefund(roundId), 100e6);
        assertEq(token.balanceOf(alice), aliceBefore + 100e6);

        uint256 bobBefore = token.balanceOf(bob);
        vm.prank(bob);
        assertEq(controller.claimRefund(roundId), 50e6);
        assertEq(token.balanceOf(bob), bobBefore + 50e6);

        vm.prank(alice);
        vm.expectRevert(LaneController.NothingToClaim.selector);
        controller.claimRefund(roundId);
    }

    function test_abortBettingRound_afterTimeout() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_twoLanePaths());
        vm.prank(alice);
        controller.buyLaneTokens(roundId, 0, 25e6);

        vm.warp(block.timestamp + controller.raceAbandonTimeout() + 1);
        controller.abortRace(roundId);

        vm.prank(alice);
        assertEq(controller.claimRefund(roundId), 25e6);
    }

    function test_ownerCanAbortEarly() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_twoLanePaths());
        vm.prank(alice);
        controller.buyLaneTokens(roundId, 0, 10e6);
        vm.prank(cre);
        controller.startRace(roundId);

        controller.abortRace(roundId);
        vm.prank(alice);
        assertEq(controller.claimRefund(roundId), 10e6);
    }

    function test_onReport_abortRace_withMetadataAllowlist() public {
        controller.setAllowedWorkflowOwner(WORKFLOW_OWNER, true);
        controller.setAllowedWorkflowId(WORKFLOW_ID, true);
        controller.setAllowedWorkflowName(WORKFLOW_NAME, true);

        vm.prank(cre);
        uint256 roundId = controller.createRound(_twoLanePaths());
        vm.prank(alice);
        controller.buyLaneTokens(roundId, 0, 10e6);

        bytes memory badMeta = _metadata(WORKFLOW_ID, WORKFLOW_NAME, address(0xBAD));
        bytes memory report = abi.encodeWithSelector(LaneController.abortRace.selector, roundId);
        vm.prank(cre);
        vm.expectRevert(abi.encodeWithSelector(CreReportAuth.UnauthorizedWorkflowOwner.selector, address(0xBAD)));
        controller.onReport(badMeta, report);

        bytes memory goodMeta = _metadata(WORKFLOW_ID, WORKFLOW_NAME, WORKFLOW_OWNER);
        vm.prank(cre);
        controller.onReport(goodMeta, report);
        assertEq(
            uint256(controller.getRoundState(roundId)), uint256(LaneController.RoundState.Aborted)
        );
    }

    function test_onReport_emptyMetadata_okUntilAllowlistConfigured() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_twoLanePaths());
        bytes memory report = abi.encodeWithSelector(LaneController.startRace.selector, roundId);
        vm.prank(cre);
        controller.onReport("", report);
        assertEq(
            uint256(controller.getRoundState(roundId)), uint256(LaneController.RoundState.Racing)
        );
    }

    function test_executor_metadataAllowlist() public {
        MockCCIPRouter router = new MockCCIPRouter();
        LaneExecutor exec = new LaneExecutor(address(router), address(this));
        exec.setCreForwarder(cre);
        exec.setRemoteExecutor(ARBITRUM, address(exec));
        exec.setHomeConfig(SEPOLIA, SEPOLIA, address(controller), address(exec));
        controller.setHopRecorder(address(exec), true);
        vm.deal(address(exec), 1 ether);

        exec.setAllowedWorkflowOwner(WORKFLOW_OWNER, true);

        vm.prank(cre);
        uint256 roundId = controller.createRound(_twoLanePaths());
        vm.prank(cre);
        controller.startRace(roundId);

        bytes memory report =
            abi.encodeWithSelector(LaneExecutor.sendHop.selector, roundId, uint8(0), SEPOLIA);

        vm.prank(cre);
        vm.expectRevert(abi.encodeWithSelector(CreReportAuth.InvalidReportMetadata.selector, uint256(0)));
        exec.onReport("", report);

        bytes memory meta = _metadata(bytes32(0), bytes10(0), WORKFLOW_OWNER);
        vm.prank(cre);
        exec.onReport(meta, report);
        (, uint8 hops,,,,) = controller.getLane(roundId, 0);
        assertEq(hops, 1);
    }
}
