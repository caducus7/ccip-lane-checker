// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

/// @notice Allowlisted CRE report selectors for LaneController.onReport.
library CreReportAuth {
    error DisallowedReportSelector(bytes4 selector);

    function assertLaneControllerReport(bytes calldata report) internal pure {
        if (report.length < 4) revert DisallowedReportSelector(bytes4(0));
        bytes4 selector = bytes4(report[:4]);
        if (
            selector != bytes4(keccak256("createRound(uint64[][])"))
                && selector != bytes4(keccak256("startRace(uint256)"))
                && selector != bytes4(keccak256("declareWinner(uint256,uint8)"))
                && selector != bytes4(keccak256("distributePrizes(uint256)"))
                && selector != bytes4(keccak256("sweepUnclaimed(uint256)"))
        ) {
            revert DisallowedReportSelector(selector);
        }
    }

    function assertExecutorReport(bytes calldata report) internal pure {
        if (report.length < 4) revert DisallowedReportSelector(bytes4(0));
        bytes4 selector = bytes4(report[:4]);
        if (selector != bytes4(keccak256("sendHop(uint256,uint8,uint64)"))) {
            revert DisallowedReportSelector(selector);
        }
    }
}
