// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

interface ILaneToken {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function startGame(uint64 destinationChainSelector, uint256 amount, uint8 maxHops) external returns (bytes32 messageId);

    function getGameRound(uint256 gameId)
        external
        view
        returns (
            address player,
            uint256 amount,
            uint8 maxHops,
            uint8 hopsCompleted,
            uint256 totalLatency,
            uint256 lastSendTime,
            bool isActive
        );
}
