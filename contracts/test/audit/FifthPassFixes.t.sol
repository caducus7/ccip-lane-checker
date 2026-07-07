// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LaneController} from "../../src/core/LaneController.sol";
import {LaneExecutor} from "../../src/core/LaneExecutor.sol";
import {PrizeCalculator} from "../../src/libraries/PrizeCalculator.sol";
import {MockCCIPRouter} from "../../src/mocks/MockCCIPRouter.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @notice Regression tests for fifth-pass audit finding: dust-bet winner capture.
contract FifthPassFixesTest is Test {
    LaneController public controller;
    MockERC20 public token;

    address public treasury = makeAddr("treasury");
    address public gasReserve = makeAddr("gasReserve");
    address public cre = makeAddr("cre");
    address public victim = makeAddr("victim");
    address public attacker = makeAddr("attacker");
    address public executor = makeAddr("executor");

    uint64 constant SEPOLIA = 16015286601757825753;
    uint64 constant ARBITRUM = 3478487238524512106;

    uint256 internal constant ROUNDS_SLOT = 5;

    function setUp() public {
        vm.warp(1_000_000);
        token = new MockERC20("USDC", "USDC", 6);
        controller = new LaneController(address(this), address(token), treasury, gasReserve, cre);
        controller.setHopRecorder(executor, true);

        token.mint(victim, 1_000_000e6);
        token.mint(attacker, 1_000_000e6);
        vm.prank(victim);
        token.approve(address(controller), type(uint256).max);
        vm.prank(attacker);
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

    /// @dev `recordHop` auto-declares the first finisher; force a finished lane without a winner for CRE fallback.
    function _forceFinishLane(uint256 roundId, uint8 laneId) internal {
        (, , uint8 requiredHops,, ,) = controller.getLane(roundId, laneId);

        bytes32 roundBase = keccak256(abi.encode(roundId, ROUNDS_SLOT));
        bytes32 laneBase = keccak256(abi.encode(laneId, uint256(roundBase) + 6));

        uint256 laneMeta = uint256(requiredHops) | (uint256(requiredHops) << 8) | (uint256(1) << 16);
        vm.store(address(controller), bytes32(uint256(laneBase) + 1), bytes32(laneMeta));
        vm.store(address(controller), bytes32(uint256(laneBase) + 3), bytes32(block.timestamp));
    }

    function test_buyLaneTokens_rejectsBelowMinBet() public {
        uint256 roundId = _createRound();
        uint256 minBet = controller.minBet();

        vm.prank(attacker);
        vm.expectRevert(LaneController.InvalidAmount.selector);
        controller.buyLaneTokens(roundId, 0, 1);

        vm.prank(attacker);
        vm.expectRevert(LaneController.InvalidAmount.selector);
        controller.buyLaneTokens(roundId, 0, minBet - 1);

        vm.prank(attacker);
        controller.buyLaneTokens(roundId, 0, minBet);
        assertEq(controller.getLanePool(roundId, 0), minBet);
    }

    function test_dustBet_cannotCaptureWinnerShare() public {
        // Temporarily allow sub-minBet placement to exercise redirect defense for legacy dust.
        controller.setMinBet(0);

        uint256 roundId = _createRound();
        uint256 victimBet = 200e6;

        vm.prank(victim);
        controller.buyLaneTokens(roundId, 1, victimBet);
        vm.prank(attacker);
        controller.buyLaneTokens(roundId, 0, 1);

        controller.setMinBet(controller.DEFAULT_MIN_BET());

        vm.prank(cre);
        controller.startRace(roundId);
        _finishLane(roundId, 0);
        _finishLane(roundId, 1);

        vm.prank(cre);
        controller.distributePrizes(roundId);

        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(victimBet + 1);

        vm.prank(attacker);
        vm.expectRevert(LaneController.NothingToClaim.selector);
        controller.claimPrize(roundId);

        vm.prank(victim);
        uint256 claimed = controller.claimPrize(roundId);
        assertEq(claimed, p.winner + p.runnerUp, "victim receives redirected winner + runner-up shares");
        assertGt(claimed, (victimBet * 70) / 100, "attacker must not capture ~70% winner share");
    }

    function test_setCreForwarder_revokesOldHopSender() public {
        MockCCIPRouter router = new MockCCIPRouter();
        LaneExecutor laneExecutor = new LaneExecutor(address(router), address(this));
        address creA = makeAddr("creA");
        address creB = makeAddr("creB");
        uint64 dest = 999;

        laneExecutor.setCreForwarder(creA);
        laneExecutor.setRemoteExecutor(dest, address(laneExecutor));
        vm.deal(address(laneExecutor), 1 ether);

        assertTrue(laneExecutor.hopSenders(creA));

        laneExecutor.setCreForwarder(creB);
        assertFalse(laneExecutor.hopSenders(creA));
        assertTrue(laneExecutor.hopSenders(creB));

        vm.prank(creA);
        vm.expectRevert(LaneExecutor.NotAuthorized.selector);
        laneExecutor.sendHop(1, 0, dest);

        bytes memory report = abi.encodeWithSelector(LaneExecutor.sendHop.selector, uint256(1), uint8(0), dest);
        vm.prank(creB);
        laneExecutor.onReport("", report);
    }

    function test_setHopRecorder_revokesPreviousRecorder() public {
        address executorV1 = makeAddr("executorV1");
        address executorV2 = makeAddr("executorV2");

        controller.setHopRecorder(executorV1, true);
        assertTrue(controller.hopRecorders(executorV1));

        controller.setHopRecorder(executorV2, true);
        assertFalse(controller.hopRecorders(executorV1));
        assertTrue(controller.hopRecorders(executorV2));
        assertEq(controller.primaryHopRecorder(), executorV2);

        uint256 roundId = _createRound();
        vm.prank(cre);
        controller.startRace(roundId);

        vm.prank(executorV1);
        vm.expectRevert(LaneController.NotAuthorized.selector);
        controller.recordHop(roundId, 0, SEPOLIA, block.timestamp);

        vm.prank(executorV2);
        controller.recordHop(roundId, 0, SEPOLIA, block.timestamp);

        (, uint8 hopsCompleted,,,,) = controller.getLane(roundId, 0);
        assertEq(hopsCompleted, 1);
    }

    function test_declareWinner_snapshotsRunnerUpTimeout() public {
        uint256 roundId = _createRound();

        vm.prank(victim);
        controller.buyLaneTokens(roundId, 0, 100e6);
        vm.prank(cre);
        controller.startRace(roundId);

        vm.prank(executor);
        controller.recordHop(roundId, 0, SEPOLIA, block.timestamp - 120);

        (, uint8 hopsCompleted,,,, bool finishedBefore) = controller.getLane(roundId, 0);
        assertEq(hopsCompleted, 1);
        assertFalse(finishedBefore);

        _forceFinishLane(roundId, 0);
        (, uint8 hopsAfter,,,, bool finishedAfter) = controller.getLane(roundId, 0);
        assertEq(hopsAfter, 2);
        assertTrue(finishedAfter);

        vm.prank(cre);
        controller.declareWinner(roundId, 0);
        assertEq(controller.getRoundWinner(roundId), 0);

        controller.setRunnerUpSettlementTimeout(0);

        vm.prank(cre);
        vm.expectRevert(LaneController.RunnerUpPending.selector);
        controller.distributePrizes(roundId);
    }
}

import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {LaneToken} from "../../src/core/LaneToken.sol";
import {MockDeliveringCCIPRouter} from "../../src/mocks/MockDeliveringCCIPRouter.sol";
import {MockVRFCoordinatorV2Plus} from "../../src/mocks/MockVRFCoordinatorV2Plus.sol";

/// @notice Regression tests for fifth-pass audit finding: cross-chain double payout.
contract FifthPassFixesCrossChainTest is Test {
    MockDeliveringCCIPRouter public router;
    MockERC20 public token;
    MockVRFCoordinatorV2Plus public vrf;

    LaneToken public origin;
    LaneToken public remote;

    uint64 constant ORIGIN_SELECTOR = 111;
    uint64 constant REMOTE_SELECTOR = 222;

    address public attacker = makeAddr("attacker");
    address public victim = makeAddr("victim");

    uint256 constant STAKE = 10e6;
    uint256 constant VICTIM_DEPOSIT = 100e6;
    uint8 constant MAX_HOPS = 2;

    function setUp() public {
        vm.warp(1_000_000);
        router = new MockDeliveringCCIPRouter();
        token = new MockERC20("USDC", "USDC", 6);
        vrf = new MockVRFCoordinatorV2Plus();

        uint256[] memory originChains = new uint256[](2);
        originChains[0] = REMOTE_SELECTOR;
        originChains[1] = ORIGIN_SELECTOR;
        origin = new LaneToken(
            address(router), address(token), address(vrf), 1, bytes32(0), 1, ORIGIN_SELECTOR, originChains
        );

        uint256[] memory remoteChains = new uint256[](2);
        remoteChains[0] = ORIGIN_SELECTOR;
        remoteChains[1] = REMOTE_SELECTOR;
        remote = new LaneToken(
            address(router), address(token), address(vrf), 1, bytes32(0), 2, REMOTE_SELECTOR, remoteChains
        );

        origin.setRemoteLaneToken(REMOTE_SELECTOR, address(remote));
        remote.setRemoteLaneToken(ORIGIN_SELECTOR, address(origin));
        router.setChainSelector(address(origin), ORIGIN_SELECTOR);
        router.setChainSelector(address(remote), REMOTE_SELECTOR);

        vm.deal(address(origin), 1 ether);
        vm.deal(address(remote), 1 ether);

        token.mint(attacker, STAKE);
        token.mint(victim, VICTIM_DEPOSIT);
        vm.startPrank(attacker);
        token.approve(address(origin), type(uint256).max);
        origin.deposit(STAKE);
        vm.stopPrank();
        vm.startPrank(victim);
        token.approve(address(origin), type(uint256).max);
        origin.deposit(VICTIM_DEPOSIT);
        vm.stopPrank();
    }

    function _fulfillVrf(address laneToken, uint256 requestId) internal {
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 0;
        vrf.fulfillRandomWords(requestId, laneToken, randomWords);
    }

    function _deliverDelayedHopToOrigin() internal {
        bytes32 foreignKey = keccak256(abi.encode(uint256(1), address(origin), uint256(1)));
        (,,,, uint256 lastSendTime,,) = origin.getGameRound(1);

        token.mint(address(origin), STAKE);

        Client.EVMTokenAmount[] memory amounts = new Client.EVMTokenAmount[](1);
        amounts[0] = Client.EVMTokenAmount({token: address(token), amount: STAKE});

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256("delayed-hop"),
            sourceChainSelector: REMOTE_SELECTOR,
            sender: abi.encode(address(remote)),
            data: abi.encode(
                foreignKey,
                ORIGIN_SELECTOR,
                address(origin),
                uint256(1),
                attacker,
                STAKE,
                MAX_HOPS,
                lastSendTime
            ),
            destTokenAmounts: amounts
        });

        vm.prank(address(router));
        origin.ccipReceive(message);
    }

    function test_doublePayout_crossChain_blockedAfterFix() public {
        uint256 attackerStart = token.balanceOf(attacker);

        vm.prank(attacker);
        origin.startGame(REMOTE_SELECTOR, STAKE, MAX_HOPS);

        _fulfillVrf(address(remote), 1);
        _fulfillVrf(address(origin), 2);

        (,,, uint8 remoteHops,,, bool remoteActive) = remote.getGameRound(1);
        assertEq(remoteHops, MAX_HOPS);
        assertFalse(remoteActive);

        vm.prank(attacker);
        remote.withdraw(STAKE);

        _deliverDelayedHopToOrigin();

        uint256 originCredit = origin.s_balances(attacker);
        if (originCredit > 0) {
            vm.prank(attacker);
            origin.withdraw(originCredit);
        }

        uint256 attackerEnd = token.balanceOf(attacker);
        assertEq(attackerEnd - attackerStart, STAKE, "double payout blocked: attacker must receive stake once");
    }
}
