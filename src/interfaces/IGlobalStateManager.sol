// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IGlobalStateManager {
    enum StateUpdate {
        DEPOSIT_COLLATERAL
    }

    function updateCollateralDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external;

    function getUserCollateralDetails(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external returns (uint256);
}
