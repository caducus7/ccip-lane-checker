// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

/// @title ICcipRouter
/// @notice Thin boundary around the CCIP router (`IRouterClient` today).
/// @dev Single swap point for CCIP vNext: when vNext ships, point implementations at the new
///      router without touching game logic. Signatures mirror `IRouterClient` v1.6.x.
interface ICcipRouter {
    /// @notice Checks if the given chain selector is supported for sending/receiving.
    function isChainSupported(uint64 destChainSelector) external view returns (bool supported);

    /// @notice Gets the fee for a given CCIP message.
    function getFee(uint64 destinationChainSelector, Client.EVM2AnyMessage memory message)
        external
        view
        returns (uint256 fee);

    /// @notice Requests a message to be sent to the destination chain.
    function ccipSend(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message)
        external
        payable
        returns (bytes32 messageId);
}
