// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";

contract CrossChainMessageReceiver is CCIPReceiver {
    error SenderNotAllowed(address sender);
    error OnlyOwnerCanCall();

    string public text;
    address private owner;
    address lastToken;
    uint256 lastAmount;

    mapping(address => bool) private allowListedSenders;

    modifier onlyAllowListedSenders(address sender) {
        if (!allowListedSenders[sender]) revert SenderNotAllowed(sender);
        _;
    }

    constructor(address router) CCIPReceiver(router) {
        owner = msg.sender;
    }

    function allowListedSender(address _sender, bool allowed) external {
        if (msg.sender != owner) revert OnlyOwnerCanCall();
        allowListedSenders[_sender] = allowed;
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory message
    )
        internal
        override
        onlyAllowListedSenders(abi.decode(message.sender, (address)))
    {
        text = abi.decode(message.data, (string));
        if (message.destTokenAmounts.length > 0) {
            lastToken = message.destTokenAmounts[0].token;
            lastAmount = message.destTokenAmounts[0].amount;
        }
    }

    function getText() external view returns (string memory) {
        return text;
    }

    function getLastSendAmount() external view returns (uint256) {
        return lastAmount;
    }
}
