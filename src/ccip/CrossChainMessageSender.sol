// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/interfaces/IERC20.sol";
import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
using SafeERC20 for IERC20;
import {console} from "forge-std/console.sol";
import {ICrossChainMessageSender} from "./interfaces/ICrossChainMessageSender.sol";

contract CrossChainMessageSender is Ownable {
    event TokenSend(bytes32 messageId);
    error InvalidAddress();
    error InvalidSender(address);
    using SafeERC20 for IERC20;
    error NotEnoughBalance();

    /**
     * @dev address of link token
     */
    address link;

    /**
     * @dev address of router of ccip
     */
    address router;

    /**
     * @dev checking if the called is allowed to send message
     */

    mapping(address caller => bool) private isAllowed;

    modifier isCallerAllowed() {
        if (!isAllowed[msg.sender]) {
            revert InvalidSender(msg.sender);
        }
        _;
    }

    constructor(address link_, address router_) Ownable(msg.sender) {
        link = link_;
        router = router_;
        setAllowedCallers(msg.sender, true);
    }

    function setAllowedCallers(address sender, bool status) public onlyOwner {
        if (sender == address(0)) {
            revert InvalidAddress();
        }
        isAllowed[sender] = status;
    }

    /**
     * @notice Sends a cross-chain message with optional token transfer using native tokens to pay the message fee.
     * @dev This function uses Chainlink CCIP (or a similar router) to send the message to a contract on another chain.
     *      The caller must be authorized via the `isCallerAllowed` modifier.
     *      If `_amount` is greater than zero and `_token` is valid, the token is approved and included in the message payload.
     *      The function multiplies the estimated message fee by 3 to ensure buffer for volatile gas prices.
     *
     * @param receiver The address on the destination chain that should receive the message.
     * @param _data The encoded payload to be delivered to the receiver.
     * @param destinationChainSelector The unique selector ID of the destination chain.
     * @param _token The address of the token to be transferred along with the message.
     * @param _amount The amount of the token to transfer.
     *
     * @return messageId The unique ID assigned to the cross-chain message sent.
     *
     * @custom:reverts NotEnoughBalance if this contract does not have enough native token to cover the message fee.
     * @custom:emits TokenSend when the message is successfully dispatched via the router.
     */

    function sendViaNativeToken(
        address receiver,
        bytes memory _data,
        uint64 destinationChainSelector,
        address _token,
        uint256 _amount
    ) external isCallerAllowed returns (bytes32 messageId) {
        Client.EVMTokenAmount[] memory tokenAmounts;
        if (_amount > 0 && _token != address(0)) {
            tokenAmounts = new Client.EVMTokenAmount[](1);
            tokenAmounts[0] = Client.EVMTokenAmount({
                token: _token,
                amount: _amount
            });
            IERC20(_token).approve(address(router), _amount);
        } else {
            tokenAmounts = new Client.EVMTokenAmount[](0);
        }
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: _data,
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 1_000_000})
            ),
            feeToken: address(0)
        });
        uint256 fees = IRouterClient(router).getFee(
            destinationChainSelector,
            message
        ) * 3;

        if (fees > address(this).balance) revert NotEnoughBalance();

        messageId = IRouterClient(router).ccipSend{value: fees}(
            destinationChainSelector,
            message
        );

        emit TokenSend(messageId);
    }

    /**
     * @notice Sends a cross-chain message with optional token transfer using LINK as the fee token.
     * @dev This function uses the Chainlink CCIP protocol to send encoded data and optionally a token amount
     *      to a specified receiver contract on a destination chain. The contract must hold enough LINK to pay the fee.
     *      If `_amount` > 0 and `_token` is valid, it includes the token in the message payload and approves it.
     *      The CCIP fee is overestimated by 20% to ensure successful execution.
     *
     * @param receiver The address on the destination chain to receive the message.
     * @param _data ABI-encoded payload to be delivered with the message.
     * @param destinationChainSelector The selector (unique ID) of the destination chain.
     * @param _token The address of the token to transfer along with the message.
     * @param _amount The amount of the `_token` to be transferred.
     *
     * @return messageId A unique identifier for the cross-chain message sent via CCIP.
     *
     * @custom:requires Caller must be the contract owner (enforced by `onlyOwner` modifier).
     * @custom:emits TokenSend Emitted after successfully sending the message through the router.
     */

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
            IERC20(_token).approve(address(router), _amount);
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

        uint256 fee = (IRouterClient(router).getFee(
            destinationChainSelector,
            message
        ) * 12) / 10;

        IERC20(link).approve(address(router), fee);

        messageId = IRouterClient(router).ccipSend(
            destinationChainSelector,
            message
        );
        emit TokenSend(messageId);
    }

    /**
     * @notice Estimates the CCIP fee required to send a cross-chain message with optional token transfer.
     * @dev Constructs a `Client.EVM2AnyMessage` with the provided parameters and queries the router
     *      for the cost of sending this message. Supports both LINK and native token as fee payment options.
     *
     * @param receiver The destination contract address on the target chain.
     * @param _data ABI-encoded payload to be sent with the message.
     * @param destinationChainSelector The unique chain selector for the destination chain.
     * @param _token The address of the token to send along with the message (can be address(0) for none).
     * @param _amount The amount of the token to transfer (must be > 0 if token is provided).
     * @param isLink A boolean indicating whether to pay fees in LINK (`true`) or native gas (`false`).
     *
     * @return fees The estimated amount of fee required to send the message via CCIP.
     *
     * @custom:requires Caller must be the contract owner (enforced by `onlyOwner` modifier).
     */

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
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 500_000})
            ),
            feeToken: isLink ? link : address(0)
        });
        fees = IRouterClient(router).getFee(destinationChainSelector, message);
    }

    receive() external payable {}
}
