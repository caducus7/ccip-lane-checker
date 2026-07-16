// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

/// @notice Allowlisted CRE report selectors + Keystone metadata identity checks.
/// @dev Metadata layout (production KeystoneForwarder): first 62 bytes are
///      `abi.encodePacked(bytes32 workflowId, bytes10 workflowName, address workflowOwner)`,
///      optionally followed by 2-byte reportId (total 64).
library CreReportAuth {
    error DisallowedReportSelector(bytes4 selector);
    error UnauthorizedWorkflowId(bytes32 workflowId);
    error UnauthorizedWorkflowName(bytes10 workflowName);
    error UnauthorizedWorkflowOwner(address workflowOwner);
    error InvalidReportMetadata(uint256 length);

    function assertLaneControllerReport(bytes calldata report) internal pure {
        if (report.length < 4) revert DisallowedReportSelector(bytes4(0));
        bytes4 selector = bytes4(report[:4]);
        if (
            selector != bytes4(keccak256("createRound(uint64[][])"))
                && selector != bytes4(keccak256("startRace(uint256)"))
                && selector != bytes4(keccak256("declareWinner(uint256,uint8)"))
                && selector != bytes4(keccak256("distributePrizes(uint256)"))
                && selector != bytes4(keccak256("sweepUnclaimed(uint256)"))
                && selector != bytes4(keccak256("abortRace(uint256)"))
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

    /// @dev Decodes Keystone metadata. Accepts 62-byte packed identity or 64-byte (+ reportId).
    function decodeMetadata(bytes calldata metadata)
        internal
        pure
        returns (bytes32 workflowId, bytes10 workflowName, address workflowOwner)
    {
        if (metadata.length < 62) revert InvalidReportMetadata(metadata.length);
        workflowId = bytes32(metadata[0:32]);
        workflowName = bytes10(metadata[32:42]);
        workflowOwner = address(bytes20(metadata[42:62]));
    }

    /// @notice When any allowlist is active, metadata must match; empty allowlists stay permissive for tests.
    function assertMetadata(
        bytes calldata metadata,
        bool idsActive,
        bool namesActive,
        bool ownersActive,
        mapping(bytes32 => bool) storage allowedIds,
        mapping(bytes10 => bool) storage allowedNames,
        mapping(address => bool) storage allowedOwners
    ) internal view {
        if (!idsActive && !namesActive && !ownersActive) return;
        (bytes32 workflowId, bytes10 workflowName, address workflowOwner) = decodeMetadata(metadata);
        if (idsActive && !allowedIds[workflowId]) revert UnauthorizedWorkflowId(workflowId);
        if (namesActive && !allowedNames[workflowName]) revert UnauthorizedWorkflowName(workflowName);
        if (ownersActive && !allowedOwners[workflowOwner]) revert UnauthorizedWorkflowOwner(workflowOwner);
    }
}
