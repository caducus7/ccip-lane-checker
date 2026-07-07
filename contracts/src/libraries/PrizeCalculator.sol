// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

library PrizeCalculator {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant WINNER_BPS = 7000;
    uint256 internal constant PLATFORM_BPS = 1500;
    uint256 internal constant GAS_RESERVE_BPS = 1000;
    uint256 internal constant RUNNER_UP_BPS = 500;

    struct Payout {
        uint256 winner;
        uint256 platform;
        uint256 gasReserve;
        uint256 runnerUp;
    }

    function calculate(uint256 pool) internal pure returns (Payout memory payout) {
        payout.winner = (pool * WINNER_BPS) / BPS;
        payout.platform = (pool * PLATFORM_BPS) / BPS;
        payout.gasReserve = (pool * GAS_RESERVE_BPS) / BPS;
        // Remainder (5% + rounding dust) so shares always sum exactly to the pool.
        payout.runnerUp = pool - payout.winner - payout.platform - payout.gasReserve;
    }
}
