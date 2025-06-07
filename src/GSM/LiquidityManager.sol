// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LiquidityManager is Ownable {
    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => uint256 amount)))
        private s_globalDespositDetailsOfUser;

    mapping(uint256 chainId => mapping(uint64 tokenId => uint256 amount))
        private s_globalLiquidityPerToken;

    constructor() Ownable(msg.sender) {}

    function updateDepositDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external {
        s_globalDespositDetailsOfUser[chainId][user][tokenId] += amount;
        s_globalLiquidityPerToken[chainId][tokenId] += amount;
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
        return s_globalLiquidityPerToken[chainId][tokenId];
    }
}
