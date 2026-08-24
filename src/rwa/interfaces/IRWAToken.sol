// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IRWAToken
 * @notice A restricted security token whose balances can be pledged in place.
 * @dev The distinction that matters: `balanceOf` never changes when collateral
 *      is posted. `encumbered` rises instead. Nothing is transferred, so no
 *      party becomes holder of record on the borrower's behalf.
 */
interface IRWAToken is IERC20 {
    function encumberedOf(address holder) external view returns (uint256);

    function freeBalanceOf(address holder) external view returns (uint256);

    function encumber(address holder, uint256 amount) external;

    function release(address holder, uint256 amount) external;

    function forcedTransfer(address from, address to, uint256 amount, bytes32 lienId) external;
}
