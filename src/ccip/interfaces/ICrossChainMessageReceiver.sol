pragma solidity ^0.8.20;

interface ICrossChainMessageReceiver {
    function allowListedSender(address _sender, bool allowed) external;
}
