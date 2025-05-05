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

    function maxFlashLoan(
        address token
    ) external view override returns (uint256) {
        return
            s_flashLoanTokens[token]
                ? IERC20(token).balanceOf(address(this))
                : 0;
    }

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

    function _flashFee(
        address token,
        uint256 amount
    ) internal view returns (uint256) {
        return (amount * s_FlashLoanFee[token]) / 10000;
    }

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

    function supportsInterface(
        bytes4 interfaceId
    ) external pure override returns (bool) {
        return
            interfaceId == type(IERC3156FlashLender).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    function addFlashLoanToken(address token, uint256 fee) external onlyOwner {
        s_flashLoanTokens[token] = true;
        s_FlashLoanFee[token] = fee;
    }

    function removeFlashLoanToken(address token) external onlyOwner {
        s_flashLoanTokens[token] = false;
        s_FlashLoanFee[token] = 0;
    }

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
