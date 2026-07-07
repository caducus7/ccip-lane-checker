// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

interface ILaneExecutor {
    function laneController() external view returns (address);
    function setLaneController(address controller) external;
    function setHomeConfig(
        uint64 localChainSelector,
        uint64 homeChainSelector,
        address canonicalController,
        address homeExecutor
    ) external;
    function setRemoteExecutor(uint64 chainSelector, address executor) external;
    function setHopSender(address sender, bool allowed) external;
    function sendHop(uint256 roundId, uint8 laneId, uint64 destChainSelector) external returns (bytes32 messageId);
}
