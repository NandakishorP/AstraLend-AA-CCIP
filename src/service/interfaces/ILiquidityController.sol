// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILiquidityContorller {
    function depositController(
        address tokenAddress,
        uint64 tokenId,
        address sender,
        uint256 amount
    ) external payable;

    function withDrawController(
        address tokenAddress,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external payable;
}
