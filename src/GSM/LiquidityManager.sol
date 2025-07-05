// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title LiquidityManager
/// @notice Manages liquidity deposits of users across multiple chains and tokens.
/// @dev Stores both per-user and per-token liquidity data on a per-chain basis.
contract LiquidityManager is Ownable {
    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => uint256 amount)))
        private s_globalDespositDetailsOfUser;

    mapping(uint256 chainId => mapping(uint64 tokenId => uint256 amount))
        private s_globalLiquidityPerTokenPerChain;

    mapping(uint64 tokenId => uint256 amount) private s_globalLiquidityPerToken;

    constructor() Ownable(msg.sender) {}

    /// @notice Updates the deposit records for a user and token on a specific chain.
    /// @dev Increases both the user's deposit and total liquidity for the given chain and token.
    /// @param chainId The chain on which the liquidity is being deposited.
    /// @param user The address of the user depositing the liquidity.
    /// @param tokenId The ID of the token being deposited.
    /// @param amount The amount of tokens deposited.

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

    /// @notice Returns the deposited amount of a specific token by a user on a given chain.
    /// @param chainId The chain ID to query.
    /// @param user The address of the user.
    /// @param tokenId The token ID to query.
    /// @return The amount of tokens the user has deposited on the specified chain.

    function getDepositDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256) {
        return s_globalDespositDetailsOfUser[chainId][user][tokenId];
    }

    /// @notice Returns the total liquidity of a specific token deposited across all users on a chain.
    /// @param chainId The chain ID to query.
    /// @param tokenId The token ID to query.
    /// @return The total amount of tokens deposited for the token on the specified chain.

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
