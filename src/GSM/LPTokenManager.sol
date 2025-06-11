// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title LP Token Manager
/// @notice Manages LP tokens across multiple chains and users.
/// @dev Tracks total LP tokens owned per user, per chain, and globally.
contract LPTokenManager is Ownable {
    /// @notice Total LP tokens owned by each user across all chains.
    mapping(address user => uint256 amount) private s_TotalLPTokenOwned;

    /// @notice LP tokens owned by each user on a specific chain.
    mapping(uint64 chainId => mapping(address user => uint256 amount))
        private s_LPTokenOwned;

    /// @notice Total LP tokens in circulation on each chain.
    mapping(uint64 chainId => uint256 amount) private s_LPtokenInCirculation;

    /// @notice Total LP tokens in circulation across all chains.
    uint256 private s_totalLPTokensInCirculation;

    constructor() Ownable(msg.sender) {}

    /// @notice Updates LP token records for a user and increases circulation metrics.
    /// @dev Adds `amount` to the user's LP token ownership and overall circulation.
    /// @param chainId The ID of the chain where the tokens are tracked.
    /// @param user The address of the user receiving LP tokens.
    /// @param amount The amount of LP tokens to be added.
    function updateLpTokenInCirculation(
        uint64 chainId,
        address user,
        uint256 amount
    ) external {
        s_TotalLPTokenOwned[user] += amount;
        s_LPTokenOwned[chainId][user] += amount;
        s_LPtokenInCirculation[chainId] += amount;
        s_totalLPTokensInCirculation += amount;
    }

    /// @notice Returns the total LP tokens owned by a user across all chains.
    /// @param user The address of the user.
    /// @return The total LP token amount owned by the user.

    function getLpTokensPerUser(address user) external view returns (uint256) {
        return s_TotalLPTokenOwned[user];
    }

    /// @notice Returns the LP tokens owned by a user on a specific chain.
    /// @param chainId The chain ID to query.
    /// @param user The address of the user.
    /// @return The LP token amount owned by the user on the given chain.

    function getLpTokensPerUserPerChain(
        uint64 chainId,
        address user
    ) external view returns (uint256) {
        return s_LPTokenOwned[chainId][user];
    }

    /// @notice Returns the total LP tokens in circulation for a given chain.
    /// @param chainId The chain ID to query.
    /// @return The total circulating LP tokens on that chain.

    function getTotalLpTokensInAChain(
        uint64 chainId
    ) external view returns (uint256) {
        return s_LPtokenInCirculation[chainId];
    }

    function getTotalLpTokensInCirculation() external view returns (uint256) {
        return s_totalLPTokensInCirculation;
    }

    function totalLPTokensInCirculation() external view returns (uint256) {
        return
            s_LPtokenInCirculation[11155111] + s_LPtokenInCirculation[421614];
    }
}
