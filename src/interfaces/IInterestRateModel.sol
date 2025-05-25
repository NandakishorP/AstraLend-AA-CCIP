// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IInterestRateModel {
    function getUtilizationRatio(
        uint64 tokenId
    ) external view returns (uint256);

    function getInterestRate(uint64 tokenId) external view returns (uint256);
}
