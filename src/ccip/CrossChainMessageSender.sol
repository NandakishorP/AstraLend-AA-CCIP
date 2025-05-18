// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {CrossChainMessageSenderErrors} from "../errors/Errors.sol";
import {ICrossChainMessageSender} from "./interfaces/ICrossChainMessageSender.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract CrossChainMessageSender is Ownable, ICrossChainMessageSender {
    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        string text,
        address token,
        uint256 tokenAmount,
        address feeToken,
        uint256 fees
    );
    IRouterClient public client;
    mapping(uint64 => bool) public allowlistedDestinationChains;
    uint256 public gasLimit = 200_000;

    modifier onlyAllowlistedDestinationChain(uint64 _destinationChainSelector) {
        if (!allowlistedDestinationChains[_destinationChainSelector])
            revert CrossChainMessageSenderErrors
                .CrossChainMessageSender__DestinationChainNotAllowed(
                    _destinationChainSelector
                );
        _;
    }

    modifier validateReceiver(address _receiver) {
        if (_receiver == address(0))
            revert CrossChainMessageSenderErrors
                .CrossChainMessageSender__InvalidReceiverAddress();
        _;
    }

    constructor(
        address router_,
        address _lendingPoolContract
    ) Ownable(msg.sender) {
        client = IRouterClient(router_);
        _transferOwnership(_lendingPoolContract);
    }

    // check for allowance before implementing this function
    // checking for validity of the token and other things in modifier is pending

    function sendMessageAndOrTransferTokens(
        uint64 _destinationChainSelector,
        address _receiver,
        string calldata _data,
        address _token,
        uint256 _amount
    )
        external
        payable
        onlyOwner
        onlyAllowlistedDestinationChain(_destinationChainSelector)
        validateReceiver(_receiver)
        returns (bytes32 messageId)
    {
        Client.EVM2AnyMessage memory message = _buildCCIPMessage(
            _receiver,
            _data,
            _token,
            _amount
        );
        uint256 fees = client.getFee(_destinationChainSelector, message);
        if (msg.value < fees) {
            revert CrossChainMessageSenderErrors
                .CrossChainMessageSender__InsufficentFees();
        }

        messageId = client.ccipSend{value: msg.value}(
            _destinationChainSelector,
            message
        );
        emit MessageSent(
            messageId,
            _destinationChainSelector,
            _receiver,
            _data,
            _token,
            _amount,
            address(0),
            fees
        );
    }

    function _buildCCIPMessage(
        address _receiver,
        string calldata _data,
        address _token,
        uint256 _amount
    ) private view returns (Client.EVM2AnyMessage memory) {
        Client.EVMTokenAmount[] memory tokenAmounts;
        if (_token != address(0) && _amount > 0) {
            uint256 contractBalance = IERC20(_token).balanceOf(address(this));
            if (contractBalance < _amount) {
                revert CrossChainMessageSenderErrors
                    .CrossChainMessageSender__InsufficentBalance();
            }
            tokenAmounts = new Client.EVMTokenAmount[](1);
            tokenAmounts[0] = Client.EVMTokenAmount({
                token: _token,
                amount: _amount
            });
        } else {
            tokenAmounts = new Client.EVMTokenAmount[](0);
        }
        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(_receiver),
                data: abi.encode(_data),
                tokenAmounts: tokenAmounts,
                extraArgs: Client._argsToBytes(
                    Client.EVMExtraArgsV2({
                        gasLimit: gasLimit,
                        allowOutOfOrderExecution: false
                    })
                ),
                feeToken: address(0)
            });
    }

    function allowDestinationChain(uint64 _selector) external onlyOwner {
        allowlistedDestinationChains[_selector] = true;
    }

    function disallowDestinationChain(uint64 _selector) external onlyOwner {
        allowlistedDestinationChains[_selector] = false;
    }

    function setGasLimit(uint256 _newLimit) external onlyOwner {
        gasLimit = _newLimit;
    }
}
