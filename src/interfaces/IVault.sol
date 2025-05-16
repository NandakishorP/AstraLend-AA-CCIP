// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVault {
    function depositLiquidity(
        address user,
        address token,
        uint256 amount
    ) external;

    function depositCollateral(
        address user,
        address token,
        uint256 amount
    ) external;

    function withdrawDeposit(
        address user,
        address token,
        uint256 amount
    ) external;

    function transferLoanAmount(address user, uint256 amount) external;

    function claimLoan(address user, uint256 amount) external;

    function transferCollateral(
        address user,
        address token,
        uint256 amount
    ) external;
}
