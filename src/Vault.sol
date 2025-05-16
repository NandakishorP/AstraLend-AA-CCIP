// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {VaultErrors} from "./errors/Errors.sol";
import {ILendingPoolContract} from "./interfaces/ILendingPoolContract.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Vault is ReentrancyGuard, Ownable {
    ILendingPoolContract private lendingPoolContract;
    using SafeERC20 for IERC20;

    constructor(address _lendingPoolContract) Ownable(_lendingPoolContract) {
        lendingPoolContract = ILendingPoolContract(_lendingPoolContract);
    }

    modifier onlyLendingPool(address sender) {
        if (sender != address(lendingPoolContract)) {
            revert VaultErrors.Vault__UnauthorizedAccess();
        }
        _;
    }

    function depositLiquidity(
        address user,
        address token,
        uint256 amount
    ) external payable nonReentrant onlyLendingPool(msg.sender) {
        IERC20(token).safeTransferFrom(user, address(this), amount);
    }

    function depositCollateral(
        address user,
        address token,
        uint256 amount
    ) external payable nonReentrant onlyLendingPool(msg.sender) {
        IERC20(token).safeTransferFrom(user, address(this), amount);
    }

    function withdrawDeposit(
        address user,
        address token,
        uint256 amount
    ) external nonReentrant onlyLendingPool(msg.sender) {
        IERC20(token).safeTransfer(user, amount);
    }
}
