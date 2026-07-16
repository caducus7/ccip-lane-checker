// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LaneToken} from "../../src/core/LaneToken.sol";
import {LaneExecutor} from "../../src/core/LaneExecutor.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockCCIPRouter} from "../../src/mocks/MockCCIPRouter.sol";
import {MockDeliveringCCIPRouter} from "../../src/mocks/MockDeliveringCCIPRouter.sol";
import {MockVRFCoordinatorV2Plus} from "../../src/mocks/MockVRFCoordinatorV2Plus.sol";

/// @notice Regression tests for third-pass audit findings (cross-chain custody).
contract CrossChainAccountingTest is Test {
    MockDeliveringCCIPRouter public router;
    MockERC20 public token;
    MockVRFCoordinatorV2Plus public vrf;

    LaneToken public origin;
    LaneToken public remote;

    uint64 constant ORIGIN_SELECTOR = 111;
    uint64 constant REMOTE_SELECTOR = 222;

    address public victim = makeAddr("victim");
    address public attacker = makeAddr("attacker");
    address public cre = makeAddr("cre");

    uint256 constant VICTIM_DEPOSIT = 100e6;
    uint256 constant ATTACKER_DEPOSIT = 10e6;
    uint256 constant STAKE = 10e6;

    function setUp() public {
        vm.warp(1_000_000);
        router = new MockDeliveringCCIPRouter();
        token = new MockERC20("USDC", "USDC", 6);
        vrf = new MockVRFCoordinatorV2Plus();

        uint256[] memory originChains = new uint256[](1);
        originChains[0] = REMOTE_SELECTOR;
        origin = new LaneToken(
            address(router), address(token), address(vrf), 1, bytes32(0), 1, ORIGIN_SELECTOR, originChains
        );

        uint256[] memory remoteChains = new uint256[](1);
        remoteChains[0] = ORIGIN_SELECTOR;
        remote = new LaneToken(
            address(router), address(token), address(vrf), 1, bytes32(0), 2, REMOTE_SELECTOR, remoteChains
        );

        origin.setRemoteLaneToken(REMOTE_SELECTOR, address(remote));
        remote.setRemoteLaneToken(ORIGIN_SELECTOR, address(origin));
        router.setChainSelector(address(origin), ORIGIN_SELECTOR);
        router.setChainSelector(address(remote), REMOTE_SELECTOR);

        vm.deal(address(origin), 1 ether);
        vm.deal(address(remote), 1 ether);

        token.mint(victim, VICTIM_DEPOSIT);
        token.mint(attacker, ATTACKER_DEPOSIT);

        vm.startPrank(victim);
        token.approve(address(origin), type(uint256).max);
        origin.deposit(VICTIM_DEPOSIT);
        vm.stopPrank();

        vm.startPrank(attacker);
        token.approve(address(origin), type(uint256).max);
        origin.deposit(ATTACKER_DEPOSIT);
        vm.stopPrank();
    }

    function test_originAbandon_afterRemoteFinish_reverts() public {
        vm.prank(attacker);
        origin.startGame(REMOTE_SELECTOR, STAKE, 1);

        (,,,,,, bool remoteActive) = remote.getGameRound(1);
        assertFalse(remoteActive);

        vm.prank(attacker);
        remote.withdraw(STAKE);

        vm.warp(block.timestamp + origin.GAME_ABANDON_TIMEOUT() + 1);
        vm.prank(attacker);
        vm.expectRevert(LaneToken.GameNotAbandonable.selector);
        origin.abandonGame(1);
    }

    function test_withdraw_reservesTokensInPlay_beforeGhostAbandon() public {
        vm.prank(attacker);
        origin.startGame(REMOTE_SELECTOR, STAKE, 3);

        assertEq(origin.s_tokensInPlay(), 0);

        vm.prank(victim);
        origin.withdraw(VICTIM_DEPOSIT);
        assertEq(token.balanceOf(victim), VICTIM_DEPOSIT);
    }

    function test_executorOnReport_canDispatchSendHop() public {
        MockCCIPRouter plainRouter = new MockCCIPRouter();
        LaneExecutor localExecutor = new LaneExecutor(address(plainRouter), address(this));
        localExecutor.setCreForwarder(cre);
        localExecutor.setHopSender(cre, true);
        localExecutor.setAllowCcipLocalLoopback(true);
        localExecutor.setRemoteExecutor(REMOTE_SELECTOR, address(localExecutor));
        vm.deal(address(localExecutor), 1 ether);

        bytes memory report = abi.encodeWithSelector(LaneExecutor.sendHop.selector, uint256(1), uint8(0), REMOTE_SELECTOR);
        vm.prank(cre);
        localExecutor.onReport("", report);
    }

    function test_abandonGame_blockedUntilTimeoutAfterHop() public {
        vm.prank(attacker);
        origin.startGame(REMOTE_SELECTOR, STAKE, 2);

        vm.prank(attacker);
        vm.expectRevert(LaneToken.GameNotAbandonable.selector);
        remote.abandonGame(1);
    }

    function test_startGame_rejectsZeroAmount() public {
        vm.prank(attacker);
        vm.expectRevert(LaneToken.InvalidAmount.selector);
        origin.startGame(REMOTE_SELECTOR, 0, 1);
    }
}
