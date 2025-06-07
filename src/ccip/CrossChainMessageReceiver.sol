// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {ILendingPoolContract} from "../interfaces/ILendingPoolContract.sol";
import {LendingPoolContract} from "../LendingPoolContract.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {console} from "forge-std/console.sol";
using SafeERC20 for IERC20;
import {ICCIPReceiver} from "./interfaces/ICCIPReceiver.sol";

contract CrossChainMessageReceiver is CCIPReceiver, Ownable {
    address lendingPoolContract;
    error SenderNotAllowed(address sender);
    event MessageReceived();

    mapping(address => bool) private allowListedSenders;

    ICCIPReceiver ccipReceiver;

    modifier onlyAllowListedSenders(address sender) {
        if (!allowListedSenders[sender]) revert SenderNotAllowed(sender);
        _;
    }

    // here we need to allow the ccip to be called and it need to be approved the ledningpool contract
    constructor(
        address router,
        address ccipReceiver_
    ) CCIPReceiver(router) Ownable(msg.sender) {
        lendingPoolContract = msg.sender;
        ccipReceiver = ICCIPReceiver(ccipReceiver_);
    }

    function allowListedSender(
        address _sender,
        bool allowed
    ) external onlyOwner {
        allowListedSenders[_sender] = allowed;
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory message
    )
        internal
        override
        onlyAllowListedSenders(abi.decode(message.sender, (address)))
    {
        ccipReceiver.ccipReceiver(message);
    }
}
