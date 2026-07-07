// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LaneController} from "../src/core/LaneController.sol";
import {StandardTokenTransfer} from "../src/libraries/StandardTokenTransfer.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {FeeOnTransferERC20} from "../src/mocks/FeeOnTransferERC20.sol";

contract StandardTokenTest is Test {
    using StandardTokenTransfer for IERC20;

    MockERC20 public token;
    FeeOnTransferERC20 public fotToken;
    LaneController public controller;

    address public treasury = makeAddr("treasury");
    address public gasReserve = makeAddr("gasReserve");
    address public cre = makeAddr("cre");
    address public player = makeAddr("player");

    uint64 constant SEPOLIA = 16015286601757825753;
    uint64 constant ARBITRUM = 3478487238524512106;

    function setUp() public {
        vm.warp(1_000_000);
        token = new MockERC20("USDC", "USDC", 6);
        fotToken = new FeeOnTransferERC20("FOT", "FOT", 6);
        controller = new LaneController(address(this), address(token), treasury, gasReserve, cre);

        token.mint(player, 1_000_000e6);
        fotToken.mint(player, 1_000_000e6);
        vm.prank(player);
        token.approve(address(controller), type(uint256).max);
        vm.prank(player);
        fotToken.approve(address(controller), type(uint256).max);
    }

    function _twoLanePaths() internal pure returns (uint64[][] memory paths) {
        paths = new uint64[][](2);
        paths[0] = new uint64[](1);
        paths[0][0] = SEPOLIA;
        paths[1] = new uint64[](1);
        paths[1][0] = ARBITRUM;
    }

    function test_mockERC20_transferFromExact_succeeds() public {
        address recipient = makeAddr("recipient");
        vm.prank(player);
        token.approve(address(this), type(uint256).max);
        IERC20(address(token)).transferFromExact(player, recipient, 100e6);
        assertEq(token.balanceOf(recipient), 100e6);
    }

    function test_buyLaneTokens_mockERC20_succeeds() public {
        vm.prank(cre);
        uint256 roundId = controller.createRound(_twoLanePaths());
        vm.prank(player);
        controller.buyLaneTokens(roundId, 0, 50e6);
        assertEq(controller.getBet(roundId, 0, player), 50e6);
        assertEq(token.balanceOf(address(controller)), 50e6);
    }

    function test_feeOnTransfer_buyLaneTokens_reverts() public {
        LaneController fotController =
            new LaneController(address(this), address(fotToken), treasury, gasReserve, cre);

        vm.prank(player);
        fotToken.approve(address(fotController), type(uint256).max);

        vm.prank(cre);
        uint256 roundId = fotController.createRound(_twoLanePaths());

        vm.startPrank(player);
        fotToken.approve(address(fotController), type(uint256).max);
        vm.expectRevert(StandardTokenTransfer.NonStandardToken.selector);
        fotController.buyLaneTokens(roundId, 0, 50e6);
        vm.stopPrank();
    }
}
