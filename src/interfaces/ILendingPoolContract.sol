// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ILendingPoolContract {
    function getTotalLiquidityPerToken(
        address token
    ) external view returns (uint256);

    function getTotalBorroweedForAToken(
        address token
    ) external view returns (uint256);

    function getPriceFeedAddress(address token) external view returns (address);
}
