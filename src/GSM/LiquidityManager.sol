// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LiquidityManager is Ownable {
    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => uint256 amount)))
        private s_globalDespositDetailsOfUser;

    mapping(uint256 chainId => mapping(uint64 tokenId => uint256 amount))
        private s_globalLiquidityPerTokenPerChain;

    mapping(uint64 tokenId => uint256 amount) private s_globalLiquidityPerToken;

    constructor() Ownable(msg.sender) {}

    function updateDepositDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external {
        s_globalDespositDetailsOfUser[chainId][user][tokenId] += amount;
        s_globalLiquidityPerTokenPerChain[chainId][tokenId] += amount;
        s_globalLiquidityPerToken[tokenId] += amount;
    }

    function addLiquidity(
        uint256 chainId,
        uint64 tokenId,
        uint256 amount
    ) external onlyOwner {
        s_globalLiquidityPerTokenPerChain[chainId][tokenId] += amount;
        s_globalLiquidityPerToken[tokenId] += amount;
    }

    function removeLiquidity(
        uint256 chainId,
        uint64 tokenId,
        uint256 amount
    ) external onlyOwner {
        s_globalLiquidityPerTokenPerChain[chainId][tokenId] -= amount;
        s_globalLiquidityPerToken[tokenId] -= amount;
    }

    function updateWithDrawDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external onlyOwner {
        s_globalDespositDetailsOfUser[chainId][user][tokenId] -= amount;
        s_globalLiquidityPerTokenPerChain[chainId][tokenId] -= amount;
        s_globalLiquidityPerToken[tokenId] -= amount;
    }

    function getDepositDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256) {
        return s_globalDespositDetailsOfUser[chainId][user][tokenId];
    }

    function getTotalLiquidityPerChainPerToken(
        uint256 chainId,
        uint64 tokenId
    ) external view returns (uint256) {
        return s_globalLiquidityPerTokenPerChain[chainId][tokenId];
    }

    function getTotalLiquidityPerToken(
        uint64 tokenId
    ) external view returns (uint256) {
        return s_globalLiquidityPerToken[tokenId];
    }
}
