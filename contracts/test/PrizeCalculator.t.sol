// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PrizeCalculator} from "../src/libraries/PrizeCalculator.sol";

contract PrizeCalculatorTest is Test {
    uint256 constant MAX_POOL = type(uint256).max / PrizeCalculator.BPS;

    function test_calculate_1000() public pure {
        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(1000);
        assertEq(p.winner, 700);
        assertEq(p.platform, 150);
        assertEq(p.gasReserve, 100);
        assertEq(p.runnerUp, 50);
    }

    function test_calculate_zeroPool() public pure {
        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(0);
        assertEq(p.winner + p.platform + p.gasReserve + p.runnerUp, 0);
    }

    /// @dev Conservation: shares always sum exactly to the pool (rounding dust goes to runner-up).
    function testFuzz_calculate_conservation(uint256 pool) public pure {
        pool = bound(pool, 0, MAX_POOL);
        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(pool);
        assertEq(p.winner + p.platform + p.gasReserve + p.runnerUp, pool);
    }

    /// @dev Exact splits at the configured basis points.
    function testFuzz_calculate_shares(uint256 pool) public pure {
        pool = bound(pool, 0, MAX_POOL);
        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(pool);
        assertEq(p.winner, (pool * PrizeCalculator.WINNER_BPS) / PrizeCalculator.BPS);
        assertEq(p.platform, (pool * PrizeCalculator.PLATFORM_BPS) / PrizeCalculator.BPS);
        assertEq(p.gasReserve, (pool * PrizeCalculator.GAS_RESERVE_BPS) / PrizeCalculator.BPS);
    }

    /// @dev Ordering invariant: winner >= platform >= gasReserve >= runnerUp for non-dust pools.
    function testFuzz_calculate_ordering(uint256 pool) public pure {
        pool = bound(pool, PrizeCalculator.BPS, MAX_POOL);
        PrizeCalculator.Payout memory p = PrizeCalculator.calculate(pool);
        assertGe(p.winner, p.platform);
        assertGe(p.platform, p.gasReserve);
        // Runner-up carries rounding dust (< 4 wei), so compare with tolerance.
        assertGe(p.gasReserve + 4, p.runnerUp);
    }

    /// @dev Monotonicity: a bigger pool never pays any bucket less.
    function testFuzz_calculate_monotonic(uint256 poolA, uint256 poolB) public pure {
        poolA = bound(poolA, 0, MAX_POOL - 1);
        poolB = bound(poolB, poolA + 1, MAX_POOL);
        PrizeCalculator.Payout memory a = PrizeCalculator.calculate(poolA);
        PrizeCalculator.Payout memory b = PrizeCalculator.calculate(poolB);
        assertGe(b.winner, a.winner);
        assertGe(b.platform, a.platform);
        assertGe(b.gasReserve, a.gasReserve);
    }
}
