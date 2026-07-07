// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {LaneController} from "../../src/core/LaneController.sol";
import {LaneExecutor} from "../../src/core/LaneExecutor.sol";
import {LaneToken} from "../../src/core/LaneToken.sol";
import {MockCCIPRouter} from "../../src/mocks/MockCCIPRouter.sol";
import {MockDeliveringCCIPRouter} from "../../src/mocks/MockDeliveringCCIPRouter.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockVRFCoordinatorV2Plus} from "../../src/mocks/MockVRFCoordinatorV2Plus.sol";

/// @notice Regression tests for third-pass audit leads promoted to fixes.
contract ThirdPassLeadsTest is Test {
    MockCCIPRouter public router;
    LaneExecutor public executor;
    LaneController public controller;
    LaneToken public laneToken;
    MockERC20 public token;
    MockVRFCoordinatorV2Plus public vrf;

    address public treasury = makeAddr("treasury");
    address public gasReserve = makeAddr("gasReserve");
    address public cre = makeAddr("cre");
    address public player = makeAddr("player");
    address public bettor0 = makeAddr("bettor0");
    address public bettor1 = makeAddr("bettor1");
    address public bettor2 = makeAddr("bettor2");

    uint64 constant LOCAL_SELECTOR = 111;
    uint64 constant REMOTE_SELECTOR = 222;
    uint64 constant HOP_CHAIN = 333;

    function setUp() public {
        vm.warp(1_000_000);
        router = new MockCCIPRouter();
        executor = new LaneExecutor(address(router), address(this));
        token = new MockERC20("USDC", "USDC", 6);
        controller = new LaneController(address(this), address(token), treasury, gasReserve, cre);

        executor.setHomeConfig(LOCAL_SELECTOR, LOCAL_SELECTOR, address(controller), address(executor));
        controller.setHopRecorder(address(executor), true);
        executor.setRemoteExecutor(HOP_CHAIN, address(executor));
        executor.setRemoteExecutor(REMOTE_SELECTOR, address(executor));
        executor.setHopSender(cre, true);
        executor.setCreForwarder(cre);

        vrf = new MockVRFCoordinatorV2Plus();
        uint256[] memory chains = new uint256[](1);
        chains[0] = LOCAL_SELECTOR;
        laneToken = new LaneToken(
            address(router), address(token), address(vrf), 1, bytes32(0), block.chainid, LOCAL_SELECTOR, chains
        );
        laneToken.setRemoteLaneToken(LOCAL_SELECTOR, address(laneToken));

        token.mint(player, 100e6);
        vm.prank(player);
        token.approve(address(laneToken), type(uint256).max);
        vm.prank(player);
        laneToken.deposit(100e6);

        for (uint256 i = 0; i < 3; i++) {
            address bettor = i == 0 ? bettor0 : (i == 1 ? bettor1 : bettor2);
            token.mint(bettor, 100e6);
            vm.startPrank(bettor);
            token.approve(address(controller), type(uint256).max);
            vm.stopPrank();
        }
    }

    function _threeLanePaths() internal pure returns (uint64[][] memory paths) {
        paths = new uint64[][](3);
        for (uint256 i = 0; i < 3; i++) {
            paths[i] = new uint64[](1);
            paths[i][0] = HOP_CHAIN;
        }
    }

    function test_executorOnReport_respectsPause() public {
        vm.deal(address(executor), 1 ether);
        executor.pause();

        bytes memory report = abi.encodeWithSelector(LaneExecutor.sendHop.selector, uint256(1), uint8(0), HOP_CHAIN);
        vm.prank(cre);
        vm.expectRevert();
        executor.onReport("", report);
    }

    function test_inboundCcip_duplicateMessageId_reverts() public {
        bytes32 foreignKey = keccak256(abi.encode(block.chainid, address(laneToken), uint256(1)));
        bytes memory data = abi.encode(
            foreignKey,
            LOCAL_SELECTOR,
            address(laneToken),
            uint256(1),
            player,
            uint256(10e6),
            uint8(2),
            block.timestamp
        );

        Client.EVMTokenAmount[] memory amounts = new Client.EVMTokenAmount[](1);
        amounts[0] = Client.EVMTokenAmount({token: address(token), amount: 10e6});
        token.mint(address(laneToken), 10e6);

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256("dup"),
            sourceChainSelector: LOCAL_SELECTOR,
            sender: abi.encode(address(laneToken)),
            data: data,
            destTokenAmounts: amounts
        });

        vm.prank(address(router));
        laneToken.ccipReceive(message);

        vm.prank(address(router));
        vm.expectRevert(abi.encodeWithSelector(LaneToken.DuplicateMessage.selector, keccak256("dup")));
        laneToken.ccipReceive(message);
    }

    function test_fulfillRandomWords_unwiredRemote_reverts() public {
        MockDeliveringCCIPRouter deliveringRouter = new MockDeliveringCCIPRouter();
        uint256[] memory chains = new uint256[](2);
        chains[0] = LOCAL_SELECTOR;
        chains[1] = REMOTE_SELECTOR;
        LaneToken wired = new LaneToken(
            address(deliveringRouter), address(token), address(vrf), 1, bytes32(0), block.chainid, LOCAL_SELECTOR, chains
        );
        wired.setRemoteLaneToken(LOCAL_SELECTOR, address(wired));
        deliveringRouter.setChainSelector(address(wired), LOCAL_SELECTOR);

        vm.deal(address(wired), 1 ether);
        token.mint(player, 10e6);
        vm.prank(player);
        token.approve(address(wired), type(uint256).max);
        vm.prank(player);
        wired.deposit(10e6);
        vm.prank(player);
        wired.startGame(LOCAL_SELECTOR, 10e6, 2);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 1;
        vm.expectRevert(bytes("fulfillment failed"));
        vrf.fulfillRandomWords(1, address(wired), randomWords);
    }

    function test_distributePrizes_afterRunnerUpTimeout_withoutStuckLane() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_threeLanePaths());

        vm.prank(bettor0);
        controller.buyLaneTokens(roundId, 0, 50e6);
        vm.prank(bettor1);
        controller.buyLaneTokens(roundId, 1, 30e6);
        vm.prank(bettor2);
        controller.buyLaneTokens(roundId, 2, 20e6);

        vm.prank(cre);
        controller.startRace(roundId);

        vm.prank(address(executor));
        controller.recordHop(roundId, 0, HOP_CHAIN, block.timestamp);

        vm.warp(block.timestamp + controller.runnerUpSettlementTimeout() + 1);

        vm.prank(cre);
        controller.distributePrizes(roundId);

        assertEq(
            uint256(controller.getRoundState(roundId)), uint256(LaneController.RoundState.Settled)
        );
    }
}
