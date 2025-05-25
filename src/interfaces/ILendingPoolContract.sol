// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ILendingPoolContract {
    function getTotalLiquidityPerToken(
        uint64 tokenId
    ) external view returns (uint256);

    function getTotalBorroweedForAToken(
        uint64 tokenId
    ) external view returns (uint256);

    function getPriceFeedAddress(
        uint64 tokenId
    ) external view returns (address);
}
