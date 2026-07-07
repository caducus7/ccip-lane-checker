// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title StandardTokenTransfer
/// @notice Rejects fee-on-transfer, rebasing, and other non-standard ERC20 behavior.
library StandardTokenTransfer {
    using SafeERC20 for IERC20;

    error NonStandardToken();

    function transferFromExact(IERC20 token, address from, address to, uint256 amount) internal {
        uint256 balanceBefore = token.balanceOf(to);
        token.safeTransferFrom(from, to, amount);
        if (token.balanceOf(to) - balanceBefore != amount) revert NonStandardToken();
    }

    function transferExact(IERC20 token, address to, uint256 amount) internal {
        uint256 balanceBefore = token.balanceOf(to);
        token.safeTransfer(to, amount);
        if (token.balanceOf(to) - balanceBefore != amount) revert NonStandardToken();
    }
}
