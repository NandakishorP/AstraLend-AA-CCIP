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

contract CrossChainMessageReceiver is CCIPReceiver, Ownable {
    event MessageReceived(
        address sender,
        address token,
        uint256 amount,
        bytes32 messageId
    );
    error SenderNotAllowed(address sender);
    error OnlyOwnerCanCall();

    LendingPoolContract.CrossChainPayLoad public text;
    address private lendingPoolContract;
    address lastToken;
    uint256 lastAmount;

    mapping(address => bool) private allowListedSenders;

    modifier onlyAllowListedSenders(address sender) {
        if (!allowListedSenders[sender]) revert SenderNotAllowed(sender);
        _;
    }

    // here we need to allow the ccip to be called and it need to be approved the ledningpool contract
    constructor(address router) CCIPReceiver(router) Ownable(msg.sender) {
        lendingPoolContract = msg.sender;
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
        text = abi.decode(
            message.data,
            (LendingPoolContract.CrossChainPayLoad)
        );
        if (message.destTokenAmounts.length > 0) {
            lastToken = message.destTokenAmounts[0].token;
            console.log(lastToken);
            lastAmount = message.destTokenAmounts[0].amount;
        }
        console.log("message received and now ");
        address tokenAddress = ILendingPoolContract(lendingPoolContract)
            .getTokenAddressFromTokenId(text.crossChaintokenId);
        console.log(tokenAddress);
        console.log("going to print the new line");
        (bool success, bytes memory data) = tokenAddress.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );

        if (success) {
            uint256 balance = abi.decode(data, (uint256));
            console.log("balance is", balance);
        } else {
            console.log("static call to balanceOf failed");
        }
        IERC20(tokenAddress).approve(
            address(lendingPoolContract),
            text.amountToTransfer
        );
        console.log("about to enter the function");
        ILendingPoolContract(lendingPoolContract)
            .receiveTokensFromOneChainToOther(message.data);
        emit MessageReceived(
            abi.decode(message.sender, (address)),
            lastToken,
            lastAmount,
            message.messageId
        );
    }

    function getText()
        external
        view
        returns (LendingPoolContract.CrossChainPayLoad memory)
    {
        return text;
    }

    function getLastSendAmount() external view returns (uint256) {
        return lastAmount;
    }
}
