// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICrossChainMessageSender {
    function sendMessageAndOrTransferTokens(
        uint64 _destinationChainSelector,
        address _receiver,
        string calldata _data,
        address _token,
        uint256 _amount
    ) external payable returns (bytes32 messageId);
}
