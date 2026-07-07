// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

library LaneUtils {
    function indexOf(uint64[] memory path, uint64 selector) internal pure returns (bool found, uint256 index) {
        for (uint256 i = 0; i < path.length; i++) {
            if (path[i] == selector) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    function requiredHops(uint64[] memory path) internal pure returns (uint8) {
        if (path.length == 0) return 0;
        return uint8(path.length);
    }
}
