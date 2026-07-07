// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";

/// @notice Test router that transfers tokens and delivers CCIP messages synchronously.
contract MockDeliveringCCIPRouter {
    using SafeERC20 for IERC20;

    uint256 private s_messageCounter;
    uint256 public mockFee;
    mapping(address => uint64) public chainSelectorOf;

    function setMockFee(uint256 fee) external {
        mockFee = fee;
    }

    function setChainSelector(address laneToken, uint64 chainSelector) external {
        chainSelectorOf[laneToken] = chainSelector;
    }

    function getFee(uint64, Client.EVM2AnyMessage memory) external view returns (uint256) {
        return mockFee;
    }

    function ccipSend(uint64, Client.EVM2AnyMessage memory message) external payable returns (bytes32 messageId) {
        if (address(this).balance < mockFee) revert("insufficient fee");
        address sender = msg.sender;
        address receiver = abi.decode(message.receiver, (address));

        Client.EVMTokenAmount[] memory delivered = new Client.EVMTokenAmount[](message.tokenAmounts.length);
        for (uint256 i = 0; i < message.tokenAmounts.length; i++) {
            Client.EVMTokenAmount memory tokenAmount = message.tokenAmounts[i];
            IERC20(tokenAmount.token).safeTransferFrom(sender, receiver, tokenAmount.amount);
            delivered[i] = Client.EVMTokenAmount({token: tokenAmount.token, amount: tokenAmount.amount});
        }

        s_messageCounter++;
        messageId = bytes32(s_messageCounter);

        Client.Any2EVMMessage memory inbound = Client.Any2EVMMessage({
            messageId: messageId,
            sourceChainSelector: chainSelectorOf[sender],
            sender: abi.encode(sender),
            data: message.data,
            destTokenAmounts: delivered
        });

        CCIPReceiver(receiver).ccipReceive(inbound);
    }

    receive() external payable {}
}
