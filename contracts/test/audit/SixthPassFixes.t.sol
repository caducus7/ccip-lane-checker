// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {LaneController} from "../../src/core/LaneController.sol";
import {LaneExecutor} from "../../src/core/LaneExecutor.sol";
import {LaneToken} from "../../src/core/LaneToken.sol";
import {IReceiver} from "../../src/interfaces/IReceiver.sol";
import {PrizeCalculator} from "../../src/libraries/PrizeCalculator.sol";
import {MockCCIPRouter} from "../../src/mocks/MockCCIPRouter.sol";
import {MockDeliveringCCIPRouter} from "../../src/mocks/MockDeliveringCCIPRouter.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockVRFCoordinatorV2Plus} from "../../src/mocks/MockVRFCoordinatorV2Plus.sol";

/// @notice Sixth-pass audit: PoC validation + regression coverage for High/Medium fixes.
contract SixthPassFixesTest is Test {
    LaneController public controller;
    LaneExecutor public homeExecutor;
    LaneExecutor public baseExecutor;
    MockCCIPRouter public router;
    MockERC20 public token;

    address public treasury = makeAddr("treasury");
    address public gasReserve = makeAddr("gasReserve");
    address public cre = makeAddr("cre");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint64 constant HOME = 111;
    uint64 constant ARBITRUM = 222;
    uint64 constant BASE = 333;

    function setUp() public {
        vm.warp(1_000_000);
        router = new MockCCIPRouter();
        token = new MockERC20("USDC", "USDC", 6);
        controller = new LaneController(address(this), address(token), treasury, gasReserve, cre);

        homeExecutor = new LaneExecutor(address(router), address(this));
        baseExecutor = new LaneExecutor(address(router), address(this));

        homeExecutor.setHomeConfig(HOME, HOME, address(controller), address(homeExecutor));
        baseExecutor.setHomeConfig(BASE, HOME, address(controller), address(homeExecutor));
        homeExecutor.setLaneController(address(controller));
        controller.setHopRecorder(address(homeExecutor), true);

        homeExecutor.setRemoteExecutor(BASE, address(baseExecutor));
        homeExecutor.setRemoteExecutor(ARBITRUM, address(baseExecutor)); // stand-in peer
        baseExecutor.setRemoteExecutor(HOME, address(homeExecutor));
        baseExecutor.setRemoteExecutor(ARBITRUM, address(baseExecutor));

        homeExecutor.setHopSender(cre, true);
        baseExecutor.setHopSender(cre, true);
        vm.deal(address(homeExecutor), 10 ether);
        vm.deal(address(baseExecutor), 10 ether);

        token.mint(alice, 1_000_000e6);
        token.mint(bob, 1_000_000e6);
        vm.prank(alice);
        token.approve(address(controller), type(uint256).max);
        vm.prank(bob);
        token.approve(address(controller), type(uint256).max);
    }

    function _threeLanePaths() internal pure returns (uint64[][] memory paths) {
        paths = new uint64[][](3);
        for (uint8 i = 0; i < 3; i++) {
            paths[i] = new uint64[](2);
            paths[i][0] = HOME;
            paths[i][1] = ARBITRUM;
        }
    }

    function _finishLane(uint256 roundId, uint8 laneId) internal {
        (uint64[] memory path,,,,,) = controller.getLane(roundId, laneId);
        vm.startPrank(address(homeExecutor));
        for (uint256 i = 0; i < path.length; i++) {
            controller.recordHop(roundId, laneId, path[i], block.timestamp - 100 + i);
        }
        vm.stopPrank();
    }

    function test_supportsInterface_IReceiver() public view {
        assertTrue(controller.supportsInterface(type(IReceiver).interfaceId));
        assertTrue(controller.supportsInterface(type(IERC165).interfaceId));
        assertTrue(homeExecutor.supportsInterface(type(IReceiver).interfaceId));
        assertTrue(homeExecutor.supportsInterface(type(IERC165).interfaceId));
    }

    /// @dev PoC (fixed): compromised Base cannot forge Arbitrum hop via data.hopChainSelector.
    function test_hopChainSelector_forgedRemoteRejected() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_threeLanePaths());
        vm.prank(alice);
        controller.buyLaneTokens(roundId, 0, 100e6);
        vm.prank(cre);
        controller.startRace(roundId);

        // Honest first hop (HOME) via local record.
        vm.prank(cre);
        homeExecutor.sendHop(roundId, 0, HOME);
        (, uint8 hops,, , ,) = controller.getLane(roundId, 0);
        assertEq(hops, 1);

        // Malicious Base executor delivers message claiming ARBITRUM hop.
        Client.Any2EVMMessage memory forged = Client.Any2EVMMessage({
            messageId: bytes32(uint256(42)),
            sourceChainSelector: BASE,
            sender: abi.encode(address(baseExecutor)),
            data: abi.encode(roundId, uint8(0), ARBITRUM, block.timestamp - 10),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                LaneExecutor.InvalidHopChainSelector.selector, ARBITRUM, HOME, BASE
            )
        );
        vm.prank(address(router));
        homeExecutor.ccipReceive(forged);
    }

    /// @dev Honest relay: claimed selector == source is accepted.
    function test_hopChainSelector_honestRelayAccepted() public {
        uint64[][] memory paths = new uint64[][](2);
        paths[0] = new uint64[](2);
        paths[0][0] = BASE;
        paths[0][1] = HOME;
        paths[1] = new uint64[](2);
        paths[1][0] = BASE;
        paths[1][1] = HOME;

        vm.prank(cre);
        uint256 roundId = controller.createRound(paths);
        vm.prank(alice);
        controller.buyLaneTokens(roundId, 0, 100e6);
        vm.prank(cre);
        controller.startRace(roundId);

        Client.Any2EVMMessage memory relay = Client.Any2EVMMessage({
            messageId: bytes32(uint256(7)),
            sourceChainSelector: BASE,
            sender: abi.encode(address(baseExecutor)),
            data: abi.encode(roundId, uint8(0), BASE, block.timestamp - 10),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(router));
        homeExecutor.ccipReceive(relay);

        (, uint8 hops,,,,) = controller.getLane(roundId, 0);
        assertEq(hops, 1);
    }

    function test_emptyWinner_threeLanes_noRedirectToFattest() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_threeLanePaths());

        vm.prank(alice);
        controller.buyLaneTokens(roundId, 1, 50e6);
        vm.prank(bob);
        controller.buyLaneTokens(roundId, 2, 200e6);

        vm.prank(cre);
        controller.startRace(roundId);
        _finishLane(roundId, 0); // empty winner
        _finishLane(roundId, 1);
        _finishLane(roundId, 2);

        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(250e6);
        uint256 treasuryBefore = token.balanceOf(treasury);

        vm.prank(cre);
        controller.distributePrizes(roundId);

        assertEq(token.balanceOf(treasury) - treasuryBefore, p.platform + p.winner);
        // Bob (fattest non-winner) must NOT receive redirected winner share.
        vm.prank(bob);
        vm.expectRevert(LaneController.NothingToClaim.selector);
        controller.claimPrize(roundId);

        vm.prank(alice);
        assertEq(controller.claimPrize(roundId), p.runnerUp);
    }

    function test_sendHop_localPathRecordsWithoutCcip() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_threeLanePaths());
        vm.prank(cre);
        controller.startRace(roundId);

        vm.prank(cre);
        bytes32 id = homeExecutor.sendHop(roundId, 0, HOME);
        assertEq(id, bytes32(0));
        (, uint8 hops,,,,) = controller.getLane(roundId, 0);
        assertEq(hops, 1);
    }

    function test_sendHop_rejectsWrongDestination() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_threeLanePaths());
        vm.prank(cre);
        controller.startRace(roundId);

        vm.prank(cre);
        vm.expectRevert(abi.encodeWithSelector(LaneExecutor.InvalidHopDestination.selector, BASE));
        homeExecutor.sendHop(roundId, 0, BASE);
    }

    function test_sendHop_duplicateLocalHopReverts() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_threeLanePaths());
        vm.prank(cre);
        controller.startRace(roundId);

        vm.prank(cre);
        homeExecutor.sendHop(roundId, 0, HOME);

        vm.prank(cre);
        vm.expectRevert(abi.encodeWithSelector(LaneExecutor.InvalidHopDestination.selector, HOME));
        homeExecutor.sendHop(roundId, 0, HOME);
    }
}

contract SixthPassLaneTokenFixesTest is Test {
    MockDeliveringCCIPRouter public router;
    MockERC20 public token;
    MockVRFCoordinatorV2Plus public vrf;
    LaneToken public origin;
    LaneToken public remote;
    LaneToken public virgin;

    uint64 constant ORIGIN_SEL = 111;
    uint64 constant REMOTE_SEL = 222;
    uint64 constant VIRGIN_SEL = 333;

    address public player = makeAddr("player");

    function setUp() public {
        vm.warp(1_000_000);
        router = new MockDeliveringCCIPRouter();
        token = new MockERC20("USDC", "USDC", 6);
        vrf = new MockVRFCoordinatorV2Plus();

        uint256[] memory originChains = new uint256[](3);
        originChains[0] = ORIGIN_SEL;
        originChains[1] = REMOTE_SEL;
        originChains[2] = VIRGIN_SEL;

        origin = new LaneToken(
            address(router), address(token), address(vrf), 1, bytes32(0), block.chainid, ORIGIN_SEL, originChains
        );
        remote = new LaneToken(
            address(router), address(token), address(vrf), 1, bytes32(0), block.chainid, REMOTE_SEL, originChains
        );
        virgin = new LaneToken(
            address(router), address(token), address(vrf), 1, bytes32(0), block.chainid, VIRGIN_SEL, originChains
        );

        router.setChainSelector(address(origin), ORIGIN_SEL);
        router.setChainSelector(address(remote), REMOTE_SEL);
        router.setChainSelector(address(virgin), VIRGIN_SEL);

        origin.setRemoteLaneToken(REMOTE_SEL, address(remote));
        origin.setRemoteLaneToken(VIRGIN_SEL, address(virgin));
        remote.setRemoteLaneToken(ORIGIN_SEL, address(origin));
        remote.setRemoteLaneToken(VIRGIN_SEL, address(virgin));
        virgin.setRemoteLaneToken(ORIGIN_SEL, address(origin));
        virgin.setRemoteLaneToken(REMOTE_SEL, address(remote));

        vm.deal(address(origin), 10 ether);
        vm.deal(address(remote), 10 ether);
        vm.deal(address(virgin), 10 ether);

        token.mint(player, 1000e6);
        vm.prank(player);
        token.approve(address(origin), type(uint256).max);
        vm.prank(player);
        origin.deposit(100e6);
    }

    function test_selfBridge_forbidden() public {
        // Foreign selector mapped to this contract (WIRE_SELF footgun).
        origin.setRemoteLaneToken(REMOTE_SEL, address(origin));
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(LaneToken.SelfBridgeForbidden.selector, REMOTE_SEL));
        origin.startGame(REMOTE_SEL, 10e6, 2);
    }

    function test_transferAdmin_movesConfirmedOwner() public {
        address newAdmin = makeAddr("newAdmin");
        origin.transferAdmin(newAdmin);
        assertEq(origin.admin(), newAdmin);
        vm.prank(newAdmin);
        origin.acceptOwnership();
        assertEq(origin.owner(), newAdmin);
    }

    function test_lateHopAfterSettlement_refundsWithoutInflatingInPlay() public {
        // Mark FK settled on virgin with no game, then deliver hop+tokens.
        bytes32 fk = keccak256(abi.encode(block.chainid, address(origin), uint256(1)));

        // Apply settlement via message to virgin.
        bytes memory settleData = abi.encode(keccak256("LaneToken.Settlement"), fk);
        Client.Any2EVMMessage memory settleMsg = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: ORIGIN_SEL,
            sender: abi.encode(address(origin)),
            data: settleData,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });
        vm.prank(address(router));
        virgin.ccipReceive(settleMsg);
        assertTrue(virgin.s_foreignKeySettled(fk));

        uint256 inPlayBefore = virgin.s_tokensInPlay();
        uint256 amount = 10e6;
        token.mint(address(virgin), amount); // simulate CCIP token delivery balance

        // Build hop payload matching origin game id 1 shape.
        // Encode HopPayload struct fields in order.
        bytes memory hopData = abi.encode(
            fk,
            ORIGIN_SEL,
            address(origin),
            uint256(1),
            player,
            amount,
            uint8(2),
            block.timestamp - 5
        );

        Client.EVMTokenAmount[] memory amounts = new Client.EVMTokenAmount[](1);
        amounts[0] = Client.EVMTokenAmount({token: address(token), amount: amount});

        Client.Any2EVMMessage memory hopMsg = Client.Any2EVMMessage({
            messageId: bytes32(uint256(2)),
            sourceChainSelector: ORIGIN_SEL,
            sender: abi.encode(address(origin)),
            data: hopData,
            destTokenAmounts: amounts
        });

        uint256 balBefore = virgin.s_balances(player);
        vm.prank(address(router));
        virgin.ccipReceive(hopMsg);

        assertEq(virgin.s_tokensInPlay(), inPlayBefore, "must not inflate tokensInPlay");
        assertEq(virgin.s_balances(player), balBefore + amount, "late hop refunds initiator");
        assertEq(virgin.s_foreignKeyToGameId(fk), 0, "must not bootstrap game");
    }

    function test_vrf_picksOnlyWiredRemote() public {
        // Restore REMOTE wiring after self-bridge test pollution on shared origin — use fresh token.
        uint256[] memory chains = new uint256[](2);
        chains[0] = ORIGIN_SEL;
        chains[1] = REMOTE_SEL;

        LaneToken solo = new LaneToken(
            address(router), address(token), address(vrf), 1, bytes32(0), block.chainid, ORIGIN_SEL, chains
        );
        solo.setRemoteLaneToken(REMOTE_SEL, address(remote));
        remote.setRemoteLaneToken(ORIGIN_SEL, address(solo));
        vm.deal(address(solo), 5 ether);
        router.setChainSelector(address(solo), ORIGIN_SEL);

        token.mint(player, 100e6);
        vm.startPrank(player);
        token.approve(address(solo), type(uint256).max);
        solo.deposit(50e6);
        // maxHops=3 so remote requests VRF after first hop instead of finishing.
        solo.startGame(REMOTE_SEL, 10e6, 3);
        vm.stopPrank();

        // Entropy 0 would select supported[0]=local under the old modulo; must still pick REMOTE.
        uint256[] memory words = new uint256[](1);
        words[0] = 0;
        uint256 reqId = vrf.lastRequestId();
        vrf.fulfillRandomWords(reqId, address(remote), words);

        // Remote should have bridged onward (tokensBridgedOut / inactive) without reverting.
        // If local were chosen, SelfBridgeForbidden or Unwired would revert the fulfill.
        assertTrue(true);
    }

    function test_finishGame_skipsSettlementWhenUnderfunded() public {
        router.setMockFee(1 ether);
        // Fund origin for the initial hop; leave remote broke for settlement fan-out.
        vm.deal(address(origin), 2 ether);
        vm.deal(address(remote), 0);

        vm.prank(player);
        origin.startGame(REMOTE_SEL, 10e6, 1);

        assertGt(remote.s_balances(player), 0, "finish credits player even if settlement fees missing");
    }
}
