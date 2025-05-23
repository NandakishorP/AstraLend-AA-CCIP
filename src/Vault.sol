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
    address stableCoin;
    bool private paused;

    constructor(
        address lendingPoolContract_,
        address stableCoinAddress_
    ) Ownable(lendingPoolContract_) {
        lendingPoolContract = ILendingPoolContract(lendingPoolContract_);
        stableCoin = stableCoinAddress_;
    }

    modifier notPaused() {
        if (paused == true) {
            revert VaultErrors.Vault__VaultPaused();
        }
        _;
    }

    modifier onlyLendingPool() {
        if (msg.sender != address(lendingPoolContract)) {
            revert VaultErrors.Vault__UnauthorizedAccess();
        }
        _;
    }

    function depositLiquidity(
        address user,
        address token,
        uint256 amount
    ) external payable nonReentrant onlyLendingPool notPaused {
        IERC20(token).safeTransferFrom(user, address(this), amount);
    }

    function depositCollateral(
        address user,
        address token,
        uint256 amount
    ) external payable nonReentrant onlyLendingPool notPaused {
        IERC20(token).safeTransferFrom(user, address(this), amount);
    }

    function withdrawDeposit(
        address user,
        address token,
        uint256 amount
    ) external nonReentrant onlyLendingPool notPaused {
        IERC20(token).safeTransfer(user, amount);
    }

    function transferLoanAmount(
        address user,
        uint256 amount
    ) external nonReentrant onlyLendingPool notPaused {
        IERC20(stableCoin).safeTransfer(user, amount);
    }

    function claimLoan(
        address user,
        uint256 amount
    ) external nonReentrant onlyLendingPool notPaused {
        IERC20(stableCoin).transferFrom(user, address(this), amount);
    }

    function transferCollateral(
        address user,
        address token,
        uint256 amount
    ) external nonReentrant onlyLendingPool notPaused {
        IERC20(token).safeTransfer(user, amount);
    }
}
