// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC3156FlashLender, IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {FlashLenderContractErrors} from "../errors/Errors.sol";

contract FlashLenderContract is
    IERC3156FlashLender,
    ReentrancyGuard,
    IERC165,
    Ownable
{
    // errors

    bytes32 private constant CALLBACK_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    mapping(address => bool) private s_flashLoanTokens;
    mapping(address => uint256) private s_FlashLoanFee;

    event FlashLoanExecuted(
        address borrower,
        address token,
        uint256 amount,
        uint256 fee
    );

    constructor(
        address[] memory tokens_,
        uint256[] memory fee_
    ) Ownable(msg.sender) {
        for (uint256 i = 0; i < tokens_.length; i++) {
            s_flashLoanTokens[tokens_[i]] = true;
            s_FlashLoanFee[tokens_[i]] = fee_[i];
        }
    }

    /**
     * @notice Returns the maximum amount of tokens available for a flash loan.
     * @dev Checks if the given token is supported for flash loans. If supported,
     *      returns the current balance of the token held by the contract.
     *      Otherwise, returns 0.
     *
     * @param token The address of the ERC20 token to query for flash loan availability.
     * @return The maximum amount of the specified token available for flash loan.
     *
     * @inheritdoc IERC3156FlashLender
     */

    function maxFlashLoan(
        address token
    ) external view override returns (uint256) {
        return
            s_flashLoanTokens[token]
                ? IERC20(token).balanceOf(address(this))
                : 0;
    }

    /**
     * @notice Calculates the flash loan fee for a given token and amount.
     * @dev Reverts if the specified token is not supported for flash loans.
     *
     * @param token The address of the ERC20 token to be borrowed.
     * @param amount The amount of tokens for which the fee is to be calculated.
     * @return The fee amount to be paid for borrowing the specified amount.
     *
     * @inheritdoc IERC3156FlashLender
     */

    function flashFee(
        address token,
        uint256 amount
    ) external view override returns (uint256) {
        if (!s_flashLoanTokens[token]) {
            revert FlashLenderContractErrors
                .FlashLenderContract__TokenNotSupported();
        }
        return _flashFee(token, amount);
    }

    /**
     * @notice Internal function to calculate the flash loan fee for a given token and amount.
     * @dev Uses a basis points system (1 basis point = 0.01%). The fee percentage is retrieved from `s_FlashLoanFee`.
     *
     * @param token The address of the ERC20 token for which the flash loan fee is being calculated.
     * @param amount The amount of tokens being borrowed.
     * @return The calculated fee based on the specified amount and token's fee rate.
     */

    function _flashFee(
        address token,
        uint256 amount
    ) internal view returns (uint256) {
        return (amount * s_FlashLoanFee[token]) / 10000;
    }

    /**
     * @notice Executes a flash loan to a receiver contract, expecting repayment within the same transaction.
     * @dev This function adheres to the ERC-3156 flash loan standard. It performs a low-level call to transfer tokens,
     *      and also validates the callback and repayment. Handles tokens that do not return a value on transfer.
     *
     * Requirements:
     * - Token must be supported (`s_flashLoanTokens[token]` must be true).
     * - Token must be transferred successfully to the receiver.
     * - Receiver must implement `onFlashLoan` and return the correct callback value.
     * - Receiver must approve enough allowance for repayment of principal + fee.
     * - Repayment must be completed within the same transaction.
     *
     * Emits a {FlashLoanExecuted} event upon success.
     *
     * @param receiver The contract that will receive the flash loan and is expected to implement `onFlashLoan`.
     * @param token The ERC20 token address to be loaned.
     * @param amount The amount of tokens to loan.
     * @param data Arbitrary data to pass to the receiver's `onFlashLoan` function.
     * @return success Boolean indicating whether the flash loan was executed successfully.
     */

    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external override nonReentrant returns (bool) {
        if (!s_flashLoanTokens[token]) {
            revert FlashLenderContractErrors
                .FlashLenderContract__TokenNotSupported();
        }
        uint256 fee = _flashFee(token, amount);
        // trouble: weird erc 20
        (bool success, bytes memory returnData) = token.call(
            abi.encodeWithSelector(
                IERC20.transfer.selector,
                address(receiver),
                amount
            )
        );
        if (
            !success ||
            (returnData.length != 0 && !abi.decode(returnData, (bool)))
        ) {
            revert FlashLenderContractErrors
                .FlashLenderContract__TokenTransferFailed();
        }
        if (
            receiver.onFlashLoan(msg.sender, token, amount, fee, data) !=
            CALLBACK_SUCCESS
        ) {
            revert FlashLenderContractErrors
                .FlashLenderContract__CallBackFailed();
        }
        uint256 allowance = IERC20(token).allowance(
            address(receiver),
            address(this)
        );
        if (allowance < (amount + fee)) {
            revert FlashLenderContractErrors
                .FlashLenderContract__NotEnoughAllowance();
        }
        (bool success2, bytes memory returnData2) = token.call(
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                address(receiver),
                address(this),
                amount + fee
            )
        );
        if (
            !success2 ||
            (returnData2.length != 0 && !abi.decode(returnData2, (bool)))
        ) {
            revert FlashLenderContractErrors
                .FlashLenderContract__TokenRepaymentFailed();
        }

        emit FlashLoanExecuted(msg.sender, token, amount, fee);
        return true;
    }

    /**
     * @notice Checks if this contract implements the given interface.
     * @dev Implements ERC165's `supportsInterface` to declare support for ERC-3156 Flash Lender and ERC165 interfaces.
     *
     * @param interfaceId The interface identifier, as specified in ERC-165.
     * @return True if the contract supports the requested interface.
     */

    function supportsInterface(
        bytes4 interfaceId
    ) external pure override returns (bool) {
        return
            interfaceId == type(IERC3156FlashLender).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @notice Adds a token to the list of supported flash loan tokens and sets its fee.
     * @dev Only the contract owner can call this function.
     *      The `fee` is represented in basis points (1% = 100).
     *
     * @param token The address of the ERC20 token to allow for flash loans.
     * @param fee The flash loan fee for the token, in basis points (bps).
     */

    function addFlashLoanToken(address token, uint256 fee) external onlyOwner {
        s_flashLoanTokens[token] = true;
        s_FlashLoanFee[token] = fee;
    }

    /**
     * @notice Removes a token from the list of supported flash loan tokens and resets its fee.
     * @dev Only the contract owner can call this function.
     *      This disables the token from being used in future flash loans.
     *
     * @param token The address of the ERC20 token to remove.
     */

    function removeFlashLoanToken(address token) external onlyOwner {
        s_flashLoanTokens[token] = false;
        s_FlashLoanFee[token] = 0;
    }

    /**
     * @notice Withdraws a specified amount of a token from the contract to the owner's address.
     * @dev Only the contract owner can call this function.
     *      Uses a low-level call to handle non-standard ERC20s that may not return a boolean.
     *      Reverts if the transfer fails.
     *
     * @param token The address of the ERC20 token to withdraw.
     * @param amount The amount of tokens to transfer to the owner.
     */

    function withdrawToken(address token, uint256 amount) external onlyOwner {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, amount)
        );
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert FlashLenderContractErrors
                .FlashLenderContract__WithdrawFailed();
        }
    }
}
