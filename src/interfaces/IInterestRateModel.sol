// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IInterestRateModel {
    function getUtilizationRatio(address token) external view returns (uint256);

    function getInterestRate(address token) external view returns (uint256);
}
