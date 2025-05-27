// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/interfaces/IERC20.sol";
import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
using SafeERC20 for IERC20;
import {console} from "forge-std/console.sol";

contract CrossChainMessageSender is Ownable {
    event TokenSend();
    using SafeERC20 for IERC20;
    error NotEnoughBalance();
    address link;
    address router;

    constructor(address link_, address router_) Ownable(msg.sender) {
        link = link_;
        router = router_;
    }

    function sendViaNativeToken(
        address receiver,
        bytes memory _data,
        uint64 destinationChainSelector,
        address _token,
        uint256 _amount
    ) external onlyOwner returns (bytes32 messageId) {
        Client.EVMTokenAmount[] memory tokenAmounts;
        if (_amount > 0 && _token != address(0)) {
            tokenAmounts = new Client.EVMTokenAmount[](1);
            tokenAmounts[0] = Client.EVMTokenAmount({
                token: _token,
                amount: _amount
            });
        } else {
            tokenAmounts = new Client.EVMTokenAmount[](0);
        }
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: _data,
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
        emit TokenSend();
    }

    function sendViaLink(
        address receiver,
        bytes memory _data,
        uint64 destinationChainSelector,
        address _token,
        uint256 _amount
    ) external onlyOwner returns (bytes32 messageId) {
        Client.EVMTokenAmount[] memory tokenAmounts;
        if (_amount > 0 && _token != address(0)) {
            tokenAmounts = new Client.EVMTokenAmount[](1);
            tokenAmounts[0] = Client.EVMTokenAmount({
                token: _token,
                amount: _amount
            });
        } else {
            tokenAmounts = new Client.EVMTokenAmount[](0);
        }
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: _data,
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

        emit TokenSend();

        messageId = IRouterClient(router).ccipSend(
            destinationChainSelector,
            message
        );
    }

    function getFee(
        address receiver,
        bytes memory _data,
        uint64 destinationChainSelector,
        address _token,
        uint256 _amount,
        bool isLink
    ) external view onlyOwner returns (uint256 fees) {
        Client.EVMTokenAmount[] memory tokenAmounts;
        if (_amount > 0 && _token != address(0)) {
            tokenAmounts = new Client.EVMTokenAmount[](1);
            tokenAmounts[0] = Client.EVMTokenAmount({
                token: _token,
                amount: _amount
            });
        } else {
            tokenAmounts = new Client.EVMTokenAmount[](0);
        }

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: _data,
            tokenAmounts: tokenAmounts,
            extraArgs: "",
            feeToken: isLink ? link : address(0)
        });
        fees = IRouterClient(router).getFee(destinationChainSelector, message);
    }

    receive() external payable {}
}
