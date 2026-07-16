// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library PrizeCalculator {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant WINNER_BPS = 7000;
    uint256 internal constant PLATFORM_BPS = 1500;
    uint256 internal constant GAS_RESERVE_BPS = 1000;
    uint256 internal constant RUNNER_UP_BPS = 500;

    /// @dev Max pool such that `pool * BPS` cannot overflow.
    uint256 internal constant MAX_POOL = type(uint256).max / BPS;

    struct Payout {
        uint256 winner;
        uint256 platform;
        uint256 gasReserve;
        uint256 runnerUp;
    }

    error PoolTooLarge();

    function calculate(uint256 pool) internal pure returns (Payout memory payout) {
        if (pool > MAX_POOL) revert PoolTooLarge();
        payout.winner = (pool * WINNER_BPS) / BPS;
        payout.platform = (pool * PLATFORM_BPS) / BPS;
        payout.gasReserve = (pool * GAS_RESERVE_BPS) / BPS;
        // Remainder (5% + rounding dust) so shares always sum exactly to the pool.
        payout.runnerUp = pool - payout.winner - payout.platform - payout.gasReserve;
    }

    /// @dev Overflow-safe share * bet / pool.
    function proRata(uint256 share, uint256 bet, uint256 pool) internal pure returns (uint256) {
        if (share == 0 || bet == 0 || pool == 0) return 0;
        return Math.mulDiv(share, bet, pool);
    }
}
