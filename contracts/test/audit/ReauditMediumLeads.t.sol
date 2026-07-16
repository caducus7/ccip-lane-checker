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

/// @notice Medium/Lead reaudit fixes: loopback abandon, settlement reclaim, WIRE_SELF, overflow, admin 2-step.
contract ReauditMediumLeadsTest is Test {
    uint64 constant LOCAL = 111;
    uint64 constant REMOTE = 222;

    function test_prizeCalculator_rejectsOversizedPool() public {
        vm.expectRevert(PrizeCalculator.PoolTooLarge.selector);
        this._calc(PrizeCalculator.MAX_POOL + 1);
        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(PrizeCalculator.MAX_POOL);
        assertEq(p.winner + p.platform + p.gasReserve + p.runnerUp, PrizeCalculator.MAX_POOL);
    }

    function _calc(uint256 pool) external pure returns (PrizeCalculator.Payout memory) {
        return PrizeCalculator.calculate(pool);
    }

    function test_minBet_defaultsToOneWholeToken_for18Decimals() public {
        MockERC20 link = new MockERC20("LINK", "LINK", 18);
        LaneController c =
            new LaneController(address(this), address(link), makeAddr("t"), makeAddr("g"), makeAddr("cre"));
        assertEq(c.minBet(), 1e18);
    }

    function test_executor_forbidsForeignSelfWire_unlessLoopbackEnabled() public {
        MockCCIPRouter router = new MockCCIPRouter();
        LaneExecutor exec = new LaneExecutor(address(router), address(this));
        exec.setHomeConfig(LOCAL, LOCAL, makeAddr("controller"), address(exec));

        vm.expectRevert(abi.encodeWithSelector(LaneExecutor.SelfWireForbidden.selector, REMOTE));
        exec.setRemoteExecutor(REMOTE, address(exec));

        exec.setAllowCcipLocalLoopback(true);
        exec.setRemoteExecutor(REMOTE, address(exec));
        assertEq(exec.remoteExecutors(REMOTE), address(exec));
    }

    function test_executor_spokeAssert_requiresWiredDest() public {
        MockCCIPRouter router = new MockCCIPRouter();
        LaneExecutor spoke = new LaneExecutor(address(router), address(this));
        spoke.setHomeConfig(REMOTE, LOCAL, makeAddr("controller"), makeAddr("homeExec"));
        spoke.setHopSender(address(this), true);
        vm.deal(address(spoke), 1 ether);

        vm.expectRevert(abi.encodeWithSelector(LaneExecutor.UnknownDestination.selector, uint64(999)));
        spoke.sendHop(1, 0, 999);
    }

    function test_localLoopback_marksInFlight_blocksAbandon() public {
        MockCCIPRouter router = new MockCCIPRouter();
        MockERC20 token = new MockERC20("USDC", "USDC", 6);
        MockVRFCoordinatorV2Plus vrf = new MockVRFCoordinatorV2Plus();
        uint256[] memory chains = new uint256[](1);
        chains[0] = LOCAL;
        LaneToken lane =
            new LaneToken(address(router), address(token), address(vrf), 1, bytes32(0), 1, LOCAL, chains);
        lane.setRemoteLaneToken(LOCAL, address(lane));
        vm.deal(address(lane), 1 ether);

        address player = makeAddr("player");
        token.mint(player, 100e6);
        vm.startPrank(player);
        token.approve(address(lane), type(uint256).max);
        lane.deposit(50e6);
        lane.startGame(LOCAL, 10e6, 2);
        vm.stopPrank();

        (,,,,,, bool active) = lane.getGameRound(1);
        assertFalse(active, "loopback marks inactive/in-flight");

        vm.warp(block.timestamp + lane.GAME_ABANDON_TIMEOUT() + 1);
        vm.prank(player);
        vm.expectRevert(LaneToken.GameNotAbandonable.selector);
        lane.abandonGame(1);
    }

    function test_settlement_whileLocalCustody_creditsInitiator() public {
        MockDeliveringCCIPRouter router = new MockDeliveringCCIPRouter();
        MockERC20 token = new MockERC20("USDC", "USDC", 6);
        MockVRFCoordinatorV2Plus vrf = new MockVRFCoordinatorV2Plus();
        uint256[] memory originChains = new uint256[](1);
        originChains[0] = REMOTE;
        uint256[] memory remoteChains = new uint256[](1);
        remoteChains[0] = LOCAL;

        LaneToken origin =
            new LaneToken(address(router), address(token), address(vrf), 1, bytes32(0), 1, LOCAL, originChains);
        LaneToken remote =
            new LaneToken(address(router), address(token), address(vrf), 1, bytes32(0), 2, REMOTE, remoteChains);
        origin.setRemoteLaneToken(REMOTE, address(remote));
        remote.setRemoteLaneToken(LOCAL, address(origin));
        router.setChainSelector(address(origin), LOCAL);
        router.setChainSelector(address(remote), REMOTE);
        vm.deal(address(origin), 1 ether);
        vm.deal(address(remote), 1 ether);

        address player = makeAddr("player");
        uint256 stake = 10e6;
        token.mint(player, stake);
        vm.startPrank(player);
        token.approve(address(origin), type(uint256).max);
        origin.deposit(stake);
        origin.startGame(REMOTE, stake, 3);
        vm.stopPrank();

        // Return hop reactivates origin with local custody (isActive, !tokensBridgedOut).
        uint256[] memory words = new uint256[](1);
        words[0] = 0;
        vrf.fulfillRandomWords(1, address(remote), words);

        (,,,,,, bool active) = origin.getGameRound(1);
        assertTrue(active, "return hop reactivates origin");

        bytes32 fk = keccak256(abi.encode(uint256(1), address(origin), uint256(1)));
        bytes memory settleData = abi.encode(keccak256("LaneToken.Settlement"), fk);
        Client.Any2EVMMessage memory settleMsg = Client.Any2EVMMessage({
            messageId: bytes32(uint256(99)),
            sourceChainSelector: REMOTE,
            sender: abi.encode(address(remote)),
            data: settleData,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });
        vm.prank(address(router));
        origin.ccipReceive(settleMsg);

        assertEq(origin.s_balances(player), stake, "local-custody settlement reclaims to initiator");
        assertTrue(origin.s_foreignKeySettled(fk));
        (,,,,,, active) = origin.getGameRound(1);
        assertFalse(active);
    }

    function test_transferAdmin_twoStep() public {
        MockDeliveringCCIPRouter router = new MockDeliveringCCIPRouter();
        MockERC20 token = new MockERC20("USDC", "USDC", 6);
        MockVRFCoordinatorV2Plus vrf = new MockVRFCoordinatorV2Plus();
        uint256[] memory chains = new uint256[](1);
        chains[0] = LOCAL;
        LaneToken lane =
            new LaneToken(address(router), address(token), address(vrf), 1, bytes32(0), 1, LOCAL, chains);

        address next = makeAddr("next");
        lane.transferAdmin(next);
        assertEq(lane.admin(), address(this));
        assertEq(lane.pendingAdmin(), next);

        vm.prank(next);
        vm.expectRevert(LaneToken.NotAdmin.selector);
        lane.setRemoteLaneToken(REMOTE, next);

        vm.prank(next);
        lane.acceptAdmin();
        vm.prank(next);
        lane.acceptOwnership();
        assertEq(lane.admin(), next);
        assertEq(lane.owner(), next);
    }
}
