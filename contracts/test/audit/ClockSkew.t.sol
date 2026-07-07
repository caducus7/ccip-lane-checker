// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {LaneController} from "../../src/core/LaneController.sol";
import {LaneExecutor} from "../../src/core/LaneExecutor.sol";
import {MockCCIPRouter} from "../../src/mocks/MockCCIPRouter.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @dev Audit finding 3: executor accepts future sendTime within skew but controller rejected it.
contract ClockSkewTest is Test {
    MockCCIPRouter public router;
    LaneExecutor public executor;
    LaneController public controller;

    address public treasury = makeAddr("treasury");
    address public gasReserve = makeAddr("gasReserve");
    address public cre = makeAddr("cre");

    uint64 constant LOCAL_SELECTOR = 111;
    uint64 constant REMOTE_SELECTOR = 222;
    uint64 constant HOP_CHAIN = 333;

    function setUp() public {
        vm.warp(1_000_000);
        router = new MockCCIPRouter();
        executor = new LaneExecutor(address(router), address(this));

        MockERC20 token = new MockERC20("USDC", "USDC", 6);
        controller = new LaneController(address(this), address(token), treasury, gasReserve, cre);

        executor.setHomeConfig(LOCAL_SELECTOR, LOCAL_SELECTOR, address(controller), address(executor));
        controller.setHopRecorder(address(executor), true);
        executor.setRemoteExecutor(REMOTE_SELECTOR, address(executor));
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

    function test_executorFutureSendTime_recordsHopOnController() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_lanePaths());
        vm.prank(cre);
        controller.startRace(roundId);

        uint256 sendTime = block.timestamp + 10 minutes;
        Client.Any2EVMMessage memory message =
            _hopMessage(REMOTE_SELECTOR, address(executor), roundId, 0, sendTime);

        vm.prank(address(router));
        executor.ccipReceive(message);

        (, uint8 hopsCompleted,,,,) = controller.getLane(roundId, 0);
        assertEq(hopsCompleted, 1);
    }

    function test_recordHop_futureWithinSkew_accepted() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_lanePaths());
        vm.prank(cre);
        controller.startRace(roundId);

        uint256 sendTime = block.timestamp + 10 minutes;
        vm.prank(address(executor));
        controller.recordHop(roundId, 0, HOP_CHAIN, sendTime);

        (, uint8 hopsCompleted,,,,) = controller.getLane(roundId, 0);
        assertEq(hopsCompleted, 1);
    }
}
