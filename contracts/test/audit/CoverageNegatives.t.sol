// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CCIPReceiver} from "@chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {LaneController} from "../../src/core/LaneController.sol";
import {LaneExecutor} from "../../src/core/LaneExecutor.sol";
import {LaneToken} from "../../src/core/LaneToken.sol";
import {CreReportAuth} from "../../src/libraries/CreReportAuth.sol";
import {MockCCIPRouter} from "../../src/mocks/MockCCIPRouter.sol";
import {MockDeliveringCCIPRouter} from "../../src/mocks/MockDeliveringCCIPRouter.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockVRFCoordinatorV2Plus} from "../../src/mocks/MockVRFCoordinatorV2Plus.sol";

/// @dev Accepts CCIP sends without pulling ERC20 (triggers BridgeCustodyMismatch on outbound bridge).
contract MockNoPullCCIPRouter {
    uint256 private s_messageCounter;
    mapping(address => uint64) public chainSelectorOf;

    function setChainSelector(address laneToken, uint64 chainSelector) external {
        chainSelectorOf[laneToken] = chainSelector;
    }

    function getFee(uint64, Client.EVM2AnyMessage memory) external pure returns (uint256) {
        return 0;
    }

    function ccipSend(uint64, Client.EVM2AnyMessage memory) external payable returns (bytes32 messageId) {
        s_messageCounter++;
        return bytes32(s_messageCounter);
    }

    receive() external payable {}
}

interface ISelectorCcipRouter {
    function setChainSelector(address laneToken, uint64 chainSelector) external;
}

/// @notice Negative-path Foundry tests for branches Medusa fuzz rarely reaches.
contract CoverageNegativesTest is Test {
    uint64 constant ORIGIN_SELECTOR = 111;
    uint64 constant REMOTE_SELECTOR = 222;
    uint64 constant HOP_CHAIN = 333;

    uint256 constant STAKE = 10e6;
    uint8 constant MAX_HOPS = 2;

    address internal treasury = makeAddr("treasury");
    address internal gasReserve = makeAddr("gasReserve");
    address internal cre = makeAddr("cre");
    address internal stranger = makeAddr("stranger");

    LaneToken internal origin;
    LaneToken internal remote;
    MockERC20 internal token;
    address internal router;

    // ------------------------------------------------------------------ deploy

    function test_controllerConstructor_zeroBettingToken_reverts() public {
        vm.expectRevert(LaneController.ZeroAddress.selector);
        new LaneController(address(this), address(0), treasury, gasReserve, cre);
    }

    function test_controllerConstructor_zeroTreasury_reverts() public {
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);
        vm.expectRevert(LaneController.ZeroAddress.selector);
        new LaneController(address(this), address(usdc), address(0), gasReserve, cre);
    }

    function test_controllerConstructor_zeroCreForwarder_reverts() public {
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);
        vm.expectRevert(LaneController.ZeroAddress.selector);
        new LaneController(address(this), address(usdc), treasury, gasReserve, address(0));
    }

    function test_laneTokenConstructor_zeroRouter_reverts() public {
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);
        MockVRFCoordinatorV2Plus vrf = new MockVRFCoordinatorV2Plus();
        uint256[] memory chains = new uint256[](1);
        chains[0] = ORIGIN_SELECTOR;
        vm.expectRevert(abi.encodeWithSelector(CCIPReceiver.InvalidRouter.selector, address(0)));
        new LaneToken(address(0), address(usdc), address(vrf), 1, bytes32(0), 1, ORIGIN_SELECTOR, chains);
    }

    function test_laneToken_transferAdmin_zero_reverts() public {
        _deployLanePair(address(new MockDeliveringCCIPRouter()));
        vm.expectRevert("zero admin");
        origin.transferAdmin(address(0));
    }

    // ------------------------------------------------------------------ LaneController admin / CRE

    function test_controller_setCreForwarder_zero_reverts() public {
        LaneController controller = _deployController();
        vm.expectRevert(LaneController.ZeroAddress.selector);
        controller.setCreForwarder(address(0));
    }

    function test_controller_onReport_nonCre_reverts() public {
        LaneController controller = _deployController();
        bytes memory report = abi.encodeWithSelector(LaneController.distributePrizes.selector, uint256(1));
        vm.prank(stranger);
        vm.expectRevert(LaneController.NotAuthorized.selector);
        controller.onReport("", report);
    }

    function test_controller_onReport_emptyReport_reverts() public {
        LaneController controller = _deployController();
        vm.prank(cre);
        vm.expectRevert(abi.encodeWithSelector(CreReportAuth.DisallowedReportSelector.selector, bytes4(0)));
        controller.onReport("", hex"");
    }

    function test_controller_onReport_disallowedSelector_reverts() public {
        LaneController controller = _deployController();
        bytes memory report = abi.encodeWithSignature("pause()");
        vm.prank(cre);
        vm.expectRevert(
            abi.encodeWithSelector(CreReportAuth.DisallowedReportSelector.selector, bytes4(keccak256("pause()")))
        );
        controller.onReport("", report);
    }

    function test_controller_onReport_failedInnerCall_reverts() public {
        LaneController controller = _deployController();
        bytes memory report = abi.encodeWithSelector(LaneController.declareWinner.selector, uint256(999), uint8(0));
        vm.prank(cre);
        vm.expectRevert(LaneController.ReportExecutionFailed.selector);
        controller.onReport("", report);
    }

    // ------------------------------------------------------------------ LaneExecutor

    function test_executor_setCreForwarder_zero_reverts() public {
        LaneExecutor executor = new LaneExecutor(address(new MockCCIPRouter()), address(this));
        vm.expectRevert(LaneExecutor.ZeroAddress.selector);
        executor.setCreForwarder(address(0));
    }

    function test_executor_onReport_nonCre_reverts() public {
        LaneExecutor executor = new LaneExecutor(address(new MockCCIPRouter()), address(this));
        executor.setCreForwarder(cre);
        bytes memory report = abi.encodeWithSelector(LaneExecutor.sendHop.selector, uint256(1), uint8(0), HOP_CHAIN);
        vm.prank(stranger);
        vm.expectRevert(LaneExecutor.NotAuthorized.selector);
        executor.onReport("", report);
    }

    function test_executor_onReport_disallowedSelector_reverts() public {
        LaneExecutor executor = new LaneExecutor(address(new MockCCIPRouter()), address(this));
        executor.setCreForwarder(cre);
        vm.prank(cre);
        vm.expectRevert(abi.encodeWithSelector(CreReportAuth.DisallowedReportSelector.selector, bytes4(0)));
        executor.onReport("", hex"");
    }

    function test_executor_ccipReceive_beforeHomeConfig_reverts() public {
        MockCCIPRouter mockRouter = new MockCCIPRouter();
        LaneExecutor executor = new LaneExecutor(address(mockRouter), address(this));
        executor.setRemoteExecutor(REMOTE_SELECTOR, address(executor));

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256("no-home"),
            sourceChainSelector: REMOTE_SELECTOR,
            sender: abi.encode(address(executor)),
            data: abi.encode(uint256(1), uint8(0), HOP_CHAIN, block.timestamp),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(mockRouter));
        vm.expectRevert(LaneExecutor.HomeConfigNotSet.selector);
        executor.ccipReceive(message);
    }

    function test_executor_sendHop_unauthorized_reverts() public {
        LaneExecutor executor = new LaneExecutor(address(new MockCCIPRouter()), address(this));
        executor.setRemoteExecutor(HOP_CHAIN, address(executor));
        vm.deal(address(executor), 1 ether);

        vm.prank(stranger);
        vm.expectRevert(LaneExecutor.NotAuthorized.selector);
        executor.sendHop(1, 0, HOP_CHAIN);
    }

    // ------------------------------------------------------------------ LaneToken custody / settlement

    function test_laneToken_startGame_bridgeCustodyMismatch_reverts() public {
        vm.warp(1_000_000);
        _deployLanePair(address(new MockNoPullCCIPRouter()));
        address player = makeAddr("player");

        token.mint(player, STAKE);
        vm.startPrank(player);
        token.approve(address(origin), type(uint256).max);
        origin.deposit(STAKE);
        vm.expectRevert(LaneToken.BridgeCustodyMismatch.selector);
        origin.startGame(REMOTE_SELECTOR, STAKE, 2);
        vm.stopPrank();
    }

    function test_laneToken_settlementMessage_withTokens_reverts() public {
        vm.warp(1_000_000);
        _deployLanePair(address(new MockDeliveringCCIPRouter()));

        bytes32 tag = keccak256("LaneToken.Settlement");
        bytes32 foreignKey = keccak256("foreign");

        Client.EVMTokenAmount[] memory amounts = new Client.EVMTokenAmount[](1);
        amounts[0] = Client.EVMTokenAmount({token: address(token), amount: 1});

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256("settlement-with-tokens"),
            sourceChainSelector: REMOTE_SELECTOR,
            sender: abi.encode(address(remote)),
            data: abi.encode(tag, foreignKey),
            destTokenAmounts: amounts
        });

        vm.prank(router);
        vm.expectRevert(LaneToken.GameMismatch.selector);
        origin.ccipReceive(message);
    }

    function test_laneToken_recordHop_afterForeignKeySettled_noops() public {
        vm.warp(1_000_000);
        _deployLanePair(address(new MockDeliveringCCIPRouter()));
        address player = makeAddr("player");

        token.mint(player, STAKE);
        vm.startPrank(player);
        token.approve(address(origin), type(uint256).max);
        origin.deposit(STAKE);
        origin.startGame(REMOTE_SELECTOR, STAKE, MAX_HOPS);
        vm.stopPrank();

        _fulfillVrf(address(remote), 1);
        _fulfillVrf(address(origin), 2);

        vm.prank(player);
        remote.withdraw(STAKE);

        uint256 bookedBefore = origin.s_balances(player);
        _deliverDelayedHopToOrigin(player, STAKE, MAX_HOPS);
        assertEq(origin.s_balances(player), bookedBefore, "settled hop must not credit again");
    }

    function test_laneToken_finishGame_skipsSecondCredit_whenAlreadySettled() public {
        vm.warp(1_000_000);
        _deployLanePair(address(new MockDeliveringCCIPRouter()));
        address player = makeAddr("player");
        uint256 startBal = token.balanceOf(player);

        token.mint(player, STAKE);
        vm.startPrank(player);
        token.approve(address(origin), type(uint256).max);
        origin.deposit(STAKE);
        origin.startGame(REMOTE_SELECTOR, STAKE, MAX_HOPS);
        vm.stopPrank();

        _fulfillVrf(address(remote), 1);
        _fulfillVrf(address(origin), 2);

        vm.prank(player);
        remote.withdraw(STAKE);

        _deliverDelayedHopToOrigin(player, STAKE, MAX_HOPS);

        uint256 originCredit = origin.s_balances(player);
        if (originCredit > 0) {
            vm.prank(player);
            origin.withdraw(originCredit);
        }

        assertEq(token.balanceOf(player) - startBal, STAKE, "stake paid out once across chains");
    }

    // ------------------------------------------------------------------ helpers

    function _deployController() internal returns (LaneController) {
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);
        return new LaneController(address(this), address(usdc), treasury, gasReserve, cre);
    }

    MockVRFCoordinatorV2Plus internal vrf;

    function _deployLanePair(address routerAddr) internal {
        router = routerAddr;
        token = new MockERC20("USDC", "USDC", 6);
        vrf = new MockVRFCoordinatorV2Plus();

        uint256[] memory originChains = new uint256[](1);
        originChains[0] = REMOTE_SELECTOR;
        origin = new LaneToken(
            router, address(token), address(vrf), 1, bytes32(0), 1, ORIGIN_SELECTOR, originChains
        );

        uint256[] memory remoteChains = new uint256[](1);
        remoteChains[0] = ORIGIN_SELECTOR;
        remote = new LaneToken(
            router, address(token), address(vrf), 1, bytes32(0), 2, REMOTE_SELECTOR, remoteChains
        );

        origin.setRemoteLaneToken(REMOTE_SELECTOR, address(remote));
        remote.setRemoteLaneToken(ORIGIN_SELECTOR, address(origin));
        ISelectorCcipRouter(router).setChainSelector(address(origin), ORIGIN_SELECTOR);
        ISelectorCcipRouter(router).setChainSelector(address(remote), REMOTE_SELECTOR);
        vm.deal(address(origin), 1 ether);
        vm.deal(address(remote), 1 ether);
    }

    function _deliverDelayedHopToOrigin(address player, uint256 amount, uint8 maxHops) internal {
        bytes32 foreignKey = keccak256(abi.encodePacked(uint256(1), address(origin), uint256(1)));
        (,,,, uint256 lastSendTime,,) = origin.getGameRound(1);

        token.mint(address(origin), amount);

        Client.EVMTokenAmount[] memory amounts = new Client.EVMTokenAmount[](1);
        amounts[0] = Client.EVMTokenAmount({token: address(token), amount: amount});

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256("delayed-hop"),
            sourceChainSelector: REMOTE_SELECTOR,
            sender: abi.encode(address(remote)),
            data: abi.encode(
                foreignKey, ORIGIN_SELECTOR, address(origin), uint256(1), player, amount, maxHops, lastSendTime
            ),
            destTokenAmounts: amounts
        });

        vm.prank(router);
        origin.ccipReceive(message);
    }

    function _fulfillVrf(address laneToken, uint256 requestId) internal {
        uint256[] memory words = new uint256[](1);
        words[0] = 0;
        vrf.fulfillRandomWords(requestId, laneToken, words);
    }
}
