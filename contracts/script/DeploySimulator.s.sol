// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {CCIPLocalSimulator} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {WETH9} from "@chainlink/local/src/shared/WETH9.sol";
import {LinkToken} from "@chainlink/local/src/shared/LinkToken.sol";
import {BurnMintERC677Helper} from "@chainlink/local/src/ccip/BurnMintERC677Helper.sol";

/// @title DeploySimulator
/// @notice Deploys CCIPLocalSimulator on a local node (anvil) for end-to-end demos.
/// @dev Example: forge script script/DeploySimulator.s.sol:DeploySimulator --rpc-url http://localhost:8545 --broadcast
contract DeploySimulator is Script {
    function run() external returns (CCIPLocalSimulator simulator) {
        uint256 deployKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployKey);
        simulator = new CCIPLocalSimulator();
        vm.stopBroadcast();

        (
            uint64 chainSelector,
            IRouterClient sourceRouter,
            ,
            WETH9 wrappedNative,
            LinkToken linkToken,
            BurnMintERC677Helper ccipBnM,
        ) = simulator.configuration();

        console2.log("CCIPLocalSimulator:", address(simulator));
        console2.log("Chain selector:", chainSelector);
        console2.log("Router:", address(sourceRouter));
        console2.log("WETH9:", address(wrappedNative));
        console2.log("LINK:", address(linkToken));
        console2.log("CCIP-BnM:", address(ccipBnM));
    }
}
