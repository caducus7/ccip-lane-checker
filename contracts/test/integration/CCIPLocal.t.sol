// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulator} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {BurnMintERC677Helper} from "@chainlink/local/src/ccip/BurnMintERC677Helper.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {LaneToken} from "../../src/core/LaneToken.sol";
import {MockVRFCoordinatorV2Plus} from "../../src/mocks/MockVRFCoordinatorV2Plus.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

/// @notice Solo-mode round-trip through Chainlink Local's CCIPLocalSimulator:
///         startGame bridges CCIP-BnM back to the LaneToken, hops complete via the
///         simulator router, VRF v2.5 mock picks the next lane until the game finishes.
contract CCIPLocalTest is Test {
    CCIPLocalSimulator public simulator;
    LaneToken public laneToken;
    BurnMintERC677Helper public ccipBnM;
    MockVRFCoordinatorV2Plus public vrfCoordinator;

    address public player = makeAddr("player");
    uint64 public chainSelector;
    IRouterClient public sourceRouter;

    uint256 constant START_AMOUNT = 1e18;

    event GameFinished(uint256 indexed gameId, uint256 totalLatency, uint8 totalHops);

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
        vm.startPrank(player);
        ccipBnM.approve(address(laneToken), START_AMOUNT);
        laneToken.deposit(START_AMOUNT);
        vm.stopPrank();
    }

    function test_SoloRoundTrip_SingleHop() public {
        vm.prank(player);
        vm.expectEmit(true, false, false, true);
        emit GameFinished(1, 0, 1);
        laneToken.startGame(chainSelector, START_AMOUNT, 1);

        (,,, uint8 hopsCompleted,,, bool isActive) = laneToken.getGameRound(1);
        assertEq(hopsCompleted, 1);
        assertFalse(isActive);

        // Stake returned to player's game balance; withdrawable in full.
        assertEq(laneToken.s_balances(player), START_AMOUNT);
        vm.prank(player);
        laneToken.withdraw(START_AMOUNT);
        assertEq(ccipBnM.balanceOf(player), START_AMOUNT);
    }

    function test_SoloRoundTrip_MultiHopWithVrf() public {
        vm.prank(player);
        laneToken.startGame(chainSelector, START_AMOUNT, 2);

        // Hop 1 delivered synchronously by the simulator; VRF request pending.
        (,,, uint8 hopsCompleted,,, bool isActive) = laneToken.getGameRound(1);
        assertEq(hopsCompleted, 1);
        assertTrue(isActive);
        assertEq(vrfCoordinator.lastRequestId(), 1);

        // Fulfill VRF: LaneToken bridges again, simulator delivers hop 2, game finishes.
        vm.warp(block.timestamp + 300);
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 7;
        vrfCoordinator.fulfillRandomWords(1, address(laneToken), randomWords);

        (,,, hopsCompleted,,, isActive) = laneToken.getGameRound(1);
        assertEq(hopsCompleted, 2);
        assertFalse(isActive);
        assertEq(laneToken.s_balances(player), START_AMOUNT);

        // Tokens never left the LaneToken contract (simulator routes locally).
        assertEq(ccipBnM.balanceOf(address(laneToken)), START_AMOUNT);
    }

    function test_ForgedCcipSender_Reverts() public {
        vm.prank(player);
        laneToken.startGame(chainSelector, START_AMOUNT, 2);

        address attacker = makeAddr("attacker");
        Client.Any2EVMMessage memory forged = Client.Any2EVMMessage({
            messageId: keccak256("forged"),
            sourceChainSelector: chainSelector,
            sender: abi.encode(attacker),
            data: abi.encode(uint256(1), block.timestamp),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(sourceRouter));
        vm.expectRevert(
            abi.encodeWithSelector(LaneToken.UnauthorizedSource.selector, attacker, address(laneToken))
        );
        laneToken.ccipReceive(forged);
    }
}
