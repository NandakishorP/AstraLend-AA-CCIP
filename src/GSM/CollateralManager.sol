// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CollateralManager is Ownable {
    /// @dev Tracks the collateral deposited by each user per chain and per token.
    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => uint256 amount)))
        private s_globalCollateralDetailsForAUser;

    /// @dev Tracks the total collateral deposited per chain and per token ID.
    mapping(uint256 chainId => mapping(uint64 tokenID => uint256 amount))
        private s_totalCollateralDepositedInTheChain;

    /// @dev Tracks the portion of user collateral that is currently locked (e.g., for loans) per chain and token.
    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => uint256 amount)))
        private s_lockedCollateralDetails;

    mapping(uint64 tokenId => uint256 amount) private s_totalCollatearlPerToken;

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Updates the user's deposited collateral record for a given token and chain.
     * @dev Adds the deposited amount to the user's balance and updates the total for the chain.
     * @param chainId The chain on which the deposit is made.
     * @param user The address of the user depositing the collateral.
     * @param tokenId The ID representing the collateral token.
     * @param amount The amount of token being deposited.
     */
    function updateDepositCollateralDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external onlyOwner {
        s_globalCollateralDetailsForAUser[chainId][user][tokenId] += amount;
        s_totalCollateralDepositedInTheChain[chainId][tokenId] += amount;
    }

    /**
     * @notice Locks a portion of the user's deposited collateral (e.g., for taking a loan).
     * @dev Moves collateral from available to locked balance for the user.
     * @param chainId The chain on which the collateral is managed.
     * @param user The address of the user whose collateral is being locked.
     * @param tokenId The ID representing the collateral token.
     * @param amount The amount of collateral to lock.
     */
    function lockCollateralOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external onlyOwner {
        s_totalCollatearlPerToken[tokenId] += amount;
        s_globalCollateralDetailsForAUser[chainId][user][tokenId] -= amount;
        s_lockedCollateralDetails[chainId][user][tokenId] += amount;
    }

    /**
     * @notice Unlocks previously locked collateral and makes it available again to the user.
     * @dev Moves collateral from the locked balance back to the available balance.
     * @param chainId The chain on which the collateral is managed.
     * @param user The address of the user whose collateral is being unlocked.
     * @param tokenId The ID representing the collateral token.
     * @param amount The amount of collateral to unlock.
     */

    function unlockCollateralOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external onlyOwner {
        s_totalCollatearlPerToken[tokenId] -= amount;
        s_globalCollateralDetailsForAUser[chainId][user][tokenId] += amount;
        s_lockedCollateralDetails[chainId][user][tokenId] -= amount;
    }

    /**
     * @notice Updates the user's collateral record after a withdrawal.
     * @dev Deducts the withdrawn amount from both the user's available collateral and the chain's total.
     * @param chainId The chain from which the withdrawal is made.
     * @param user The address of the user withdrawing the collateral.
     * @param tokenId The ID representing the collateral token.
     * @param amount The amount of collateral withdrawn.
     */

    function updateWithdrawCollateralDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external onlyOwner {
        s_globalCollateralDetailsForAUser[chainId][user][tokenId] -= amount;
        s_totalCollateralDepositedInTheChain[chainId][tokenId] -= amount;
    }

    /**
     * @notice Retrieves the amount of collateral deposited by a user for a specific token on a chain.
     * @param chainId The chain from which to fetch the data.
     * @param user The address of the user.
     * @param tokenId The ID representing the collateral token.
     * @return The amount of available (non-locked) collateral.
     */
    function getUserCollateralDetails(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256) {
        return s_globalCollateralDetailsForAUser[chainId][user][tokenId];
    }

    /**
     * @notice Retrieves the total collateral deposited in the system for a specific chain and token.
     * @param chainId The chain for which to fetch total collateral.
     * @param tokenId The ID representing the collateral token.
     * @return The total amount of collateral deposited for that chain-token combination.
     */
    function getTotalCollateralDepositedPerChainPerToken(
        uint256 chainId,
        uint64 tokenId
    ) external view returns (uint256) {
        return s_totalCollateralDepositedInTheChain[chainId][tokenId];
    }

    function getTotalCollateralPerToken(
        uint64 tokenId
    ) external view returns (uint256) {
        return s_totalCollatearlPerToken[tokenId];
    }
}
