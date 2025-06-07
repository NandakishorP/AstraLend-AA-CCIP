// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CollateralManager is Ownable {
    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => uint256 amount)))
        private s_globalCollateralDetailsForAUser;

    mapping(uint256 chainId => mapping(uint64 tokenID => uint256 amount))
        private s_totalCollateralDepositedInTheChain;

    constructor() Ownable(msg.sender) {}

    function updateDepositCollateralDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external onlyOwner {
        s_globalCollateralDetailsForAUser[chainId][user][tokenId] += amount;
        s_totalCollateralDepositedInTheChain[chainId][tokenId] += amount;
    }

    function updateWithdrawCollateralDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external onlyOwner {
        s_globalCollateralDetailsForAUser[chainId][user][tokenId] -= amount;
        s_totalCollateralDepositedInTheChain[chainId][tokenId] -= amount;
    }

    function getUserCollateralDetails(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256) {
        return s_globalCollateralDetailsForAUser[chainId][user][tokenId];
    }

    function getTotalCollateralDepositedPerChainPerToken(
        uint256 chainId,
        uint64 tokenId
    ) external view returns (uint256) {
        return s_totalCollateralDepositedInTheChain[chainId][tokenId];
    }
}
