// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";

/// @title Collateral State Mirror
/// @notice Maintains mirrored collateral information of users from other chains.
/// @dev Used for cross-chain synchronization of collateral states.
contract CollateralStateMirror is Ownable {
    constructor() Ownable(msg.sender) {}

    /// @notice Stores collateral details for a user.
    /// @param amount The total amount of collateral.
    /// @param lastUpdatedTime The last timestamp when the collateral was updated.

    struct CollateralDetailsOfUser {
        uint256 amount;
        uint256 lastUpdatedTime;
    }

    /// @notice Maps user collateral details per chain and token.
    /// @dev Nested mapping: chainId → user address → tokenId → CollateralDetailsOfUser.

    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => CollateralDetailsOfUser)))
        private s_userCollateralDetails;

    /// @notice Updates the collateral details of a user for a specific chain and token.
    /// @dev Only callable by the owner (usually a bridge or coordinator contract).
    /// @param chainId The originating chain ID of the collateral data.
    /// @param user The user whose collateral data is being updated.
    /// @param tokenId The token ID associated with the collateral.
    /// @param collateralDetailsOfUser_ The collateral details to update with.

    function updateCollateralDetaiilsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        CollateralDetailsOfUser memory collateralDetailsOfUser_
    ) external onlyOwner {
        s_userCollateralDetails[chainId][user][
            tokenId
        ] = collateralDetailsOfUser_;
    }

    /// @notice Reads the collateral details of a user for a specific chain and token.
    /// @dev Only callable by the owner (to restrict misuse or leakage).
    /// @param chainId The chain ID of the collateral data.
    /// @param user The user's address.
    /// @param tokenId The token ID for which to retrieve collateral data.
    /// @return The `CollateralDetailsOfUser` struct containing amount and last update time.

    function readCollateralDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view onlyOwner returns (CollateralDetailsOfUser memory) {
        return s_userCollateralDetails[chainId][user][tokenId];
    }
}
