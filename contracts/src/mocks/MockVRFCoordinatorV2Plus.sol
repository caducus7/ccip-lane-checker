// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/// @notice Minimal VRF v2.5 coordinator mock: records requests, lets tests trigger fulfillment.
contract MockVRFCoordinatorV2Plus {
    uint256 public lastRequestId;
    mapping(uint256 => address) public consumers;
    mapping(uint256 => uint32) public callbackGasLimits;

    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata req)
        external
        returns (uint256 requestId)
    {
        lastRequestId++;
        requestId = lastRequestId;
        consumers[requestId] = msg.sender;
        callbackGasLimits[requestId] = req.callbackGasLimit;
    }

    function fulfillRandomWords(uint256 requestId, address consumer, uint256[] memory randomWords) public {
        // Enforce the requested callback gas limit like the real coordinator does,
        // so callbacks that would run out of gas on-chain also fail in tests.
        (bool success,) = consumer.call{gas: callbackGasLimits[requestId]}(
            abi.encodeWithSignature("rawFulfillRandomWords(uint256,uint256[])", requestId, randomWords)
        );
        require(success, "fulfillment failed");
    }
}
