// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/interfaces/IERC20.sol";
import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

contract CrossChainMessageSender {
    error NotEnoughBalance();
    address link;
    address router;

    constructor(address link_, address router_) {
        link = link_;
        router = router_;
    }

    function sendViaNativeToken(
        address receiver,
        string memory someText,
        uint64 destinationChainSelector,
        address _token,
        uint256 _amount
    ) external returns (bytes32 messageId) {
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: _token,
            amount: _amount
        });
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encode(someText),
            tokenAmounts: tokenAmounts,
            extraArgs: "",
            feeToken: address(0)
        });
        IERC20(_token).approve(address(router), _amount);
        uint256 fees = IRouterClient(router).getFee(
            destinationChainSelector,
            message
        );

        if (fees > address(this).balance) revert NotEnoughBalance();

        messageId = IRouterClient(router).ccipSend{value: fees}(
            destinationChainSelector,
            message
        );
    }

    function sendViaLink(
        address receiver,
        string memory someText,
        uint64 destinationChainSelector,
        address _token,
        uint256 _amount
    ) external returns (bytes32 messageId) {
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: _token,
            amount: _amount
        });
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encode(someText),
            tokenAmounts: tokenAmounts,
            extraArgs: "",
            feeToken: link
        });

        IERC20(_token).approve(address(router), _amount);

        uint256 fee = IRouterClient(router).getFee(
            destinationChainSelector,
            message
        );

        IERC20(link).approve(address(router), fee);

        messageId = IRouterClient(router).ccipSend(
            destinationChainSelector,
            message
        );
    }

    function getFee(
        address receiver,
        string memory someText,
        uint64 destinationChainSelector,
        address _token,
        uint256 _amount
    ) external view returns (uint256 fees) {
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: _token,
            amount: _amount
        });
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encode(someText),
            tokenAmounts: tokenAmounts,
            extraArgs: "",
            feeToken: address(0)
        });
        fees = IRouterClient(router).getFee(destinationChainSelector, message);
    }
}
