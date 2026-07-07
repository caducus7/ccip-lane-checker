// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

contract MockCCIPRouter {
    uint256 private s_messageCounter;
    uint256 public mockFee;

    function setMockFee(uint256 fee) external {
        mockFee = fee;
    }

    function getFee(uint64, Client.EVM2AnyMessage memory) public view returns (uint256) {
        return mockFee;
    }

    function ccipSend(uint64, Client.EVM2AnyMessage memory) public payable returns (bytes32) {
        s_messageCounter++;
        return bytes32(s_messageCounter);
    }
}
