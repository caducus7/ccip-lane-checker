// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {LaneController} from "../src/core/LaneController.sol";
import {LaneExecutor} from "../src/core/LaneExecutor.sol";
import {MockCCIPRouter} from "../src/mocks/MockCCIPRouter.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract MockCanonicalController {
    uint256 public recordHopCalls;
    uint256 public lastRoundId;
    uint8 public lastLaneId;
    uint64 public lastChainSelector;
    uint256 public lastSendTime;

    function paused() external pure returns (bool) {
        return false;
    }

    function recordHop(uint256 roundId, uint8 laneId, uint64 chainSelector, uint256 sendTime) external {
        recordHopCalls++;
        lastRoundId = roundId;
        lastLaneId = laneId;
        lastChainSelector = chainSelector;
        lastSendTime = sendTime;
    }
}

contract LaneExecutorTest is Test {
    MockCCIPRouter public router;
    LaneExecutor public executor;
    LaneController public controller;
    MockCanonicalController public mockCanonical;

    address public treasury = makeAddr("treasury");
    address public gasReserve = makeAddr("gasReserve");
    address public cre = makeAddr("cre");
    address public stranger = makeAddr("stranger");

    uint64 constant LOCAL_SELECTOR = 111;
    uint64 constant REMOTE_SELECTOR = 222;
    uint64 constant HOP_CHAIN = 333;

    event HopReceived(uint256 indexed roundId, uint8 indexed laneId, uint64 sourceChainSelector, uint256 latency);

    function setUp() public {
        vm.warp(1_000_000);
        router = new MockCCIPRouter();
        executor = new LaneExecutor(address(router), address(this));
        mockCanonical = new MockCanonicalController();

        MockERC20 token = new MockERC20("USDC", "USDC", 6);
        controller = new LaneController(address(this), address(token), treasury, gasReserve, cre);

        executor.setHomeConfig(LOCAL_SELECTOR, LOCAL_SELECTOR, address(controller), address(executor));
        controller.setHopRecorder(address(executor), true);
        executor.setRemoteExecutor(REMOTE_SELECTOR, address(executor));
        executor.setHopSender(cre, true);
    }

    function _lanePaths() internal pure returns (uint64[][] memory paths) {
        paths = new uint64[][](2);
        paths[0] = new uint64[](1);
        paths[0][0] = HOP_CHAIN;
        paths[1] = new uint64[](1);
        paths[1][0] = HOP_CHAIN;
    }

    function _hopMessage(uint64 sourceSelector, address sender, uint256 roundId, uint8 laneId, uint256 sendTime)
        internal
        pure
        returns (Client.Any2EVMMessage memory)
    {
        return Client.Any2EVMMessage({
            messageId: keccak256("hop"),
            sourceChainSelector: sourceSelector,
            sender: abi.encode(sender),
            data: abi.encode(roundId, laneId, HOP_CHAIN, sendTime),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });
    }

    function _deliverHop(Client.Any2EVMMessage memory message) internal {
        vm.prank(address(router));
        executor.ccipReceive(message);
    }

    function test_homeChainReceive_recordsHopOnCanonicalController() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_lanePaths());
        vm.prank(cre);
        controller.startRace(roundId);

        uint256 sendTime = block.timestamp - 30;
        Client.Any2EVMMessage memory message =
            _hopMessage(REMOTE_SELECTOR, address(executor), roundId, 0, sendTime);

        vm.expectEmit(true, true, true, true);
        emit HopReceived(roundId, 0, REMOTE_SELECTOR, 30);
        _deliverHop(message);

        (, uint8 hopsCompleted,,,,) = controller.getLane(roundId, 0);
        assertEq(hopsCompleted, 1);
    }

    function test_setHomeConfig_zeroCanonicalController_reverts() public {
        vm.expectRevert(LaneExecutor.ZeroAddress.selector);
        executor.setHomeConfig(LOCAL_SELECTOR, LOCAL_SELECTOR, address(0), address(executor));
    }

    function test_setHomeConfig_zeroHomeExecutor_reverts() public {
        vm.expectRevert(LaneExecutor.ZeroAddress.selector);
        executor.setHomeConfig(LOCAL_SELECTOR, LOCAL_SELECTOR, address(controller), address(0));
    }

    function test_ccipReceive_sendTimeWithinSkew_passes() public {
        executor.setHomeConfig(LOCAL_SELECTOR, LOCAL_SELECTOR, address(mockCanonical), address(executor));

        uint256 sendTime = block.timestamp + 10 minutes;
        _deliverHop(_hopMessage(REMOTE_SELECTOR, address(executor), 1, 0, sendTime));

        assertEq(mockCanonical.recordHopCalls(), 1);
        assertEq(mockCanonical.lastSendTime(), block.timestamp);
    }

    function test_ccipReceive_sendTimeBeyondSkew_reverts() public {
        executor.setHomeConfig(LOCAL_SELECTOR, LOCAL_SELECTOR, address(mockCanonical), address(executor));

        uint256 sendTime = block.timestamp + 15 minutes + 1;
        vm.expectRevert(LaneExecutor.InvalidSendTime.selector);
        _deliverHop(_hopMessage(REMOTE_SELECTOR, address(executor), 1, 0, sendTime));
        assertEq(mockCanonical.recordHopCalls(), 0);
    }

    function test_sendHop_unauthorizedSender_reverts() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_lanePaths());
        vm.prank(cre);
        controller.startRace(roundId);

        executor.setRemoteExecutor(HOP_CHAIN, address(executor));

        vm.prank(stranger);
        vm.expectRevert(LaneExecutor.NotAuthorized.selector);
        executor.sendHop(roundId, 0, HOP_CHAIN);
    }

    function test_setHomeConfig_syncsLaneControllerOnHomeChain() public {
        LaneExecutor fresh = new LaneExecutor(address(router), address(this));
        fresh.setHomeConfig(LOCAL_SELECTOR, LOCAL_SELECTOR, address(controller), address(fresh));
        assertEq(fresh.laneController(), address(controller));
    }

    function test_onReport_sendHop_selfCall_succeeds() public {
        executor.setCreForwarder(cre);
        executor.setRemoteExecutor(HOP_CHAIN, address(executor));
        vm.deal(address(executor), 1 ether);

        vm.prank(cre);
        uint256 roundId = controller.createRound(_lanePaths());
        vm.prank(cre);
        controller.startRace(roundId);

        bytes memory report = abi.encodeWithSelector(LaneExecutor.sendHop.selector, roundId, uint8(0), HOP_CHAIN);
        vm.prank(cre);
        executor.onReport("", report);
    }
}
