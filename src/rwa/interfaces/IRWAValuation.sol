// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title IRWAValuation
 * @notice Price source for a real-world instrument.
 * @dev Extends Chainlink's AggregatorV3Interface on purpose. LendingPoolContract
 *      prices every asset through `AggregatorV3Interface(s_priceFeed[tokenId])`,
 *      so a valuation source that satisfies that interface needs no change
 *      anywhere downstream — collateral valuation, health factors, liquidation
 *      and the keeper all keep working untouched.
 *
 *      Prices carry 8 decimals, matching Chainlink feeds, because the pool
 *      scales by ADDITIONAL_PRICEFEED_PRECISION = 1e10 to reach 18.
 *
 *      The maturity accessors are the addition. An instrument that matures can
 *      redeem itself out from under a loan, so the pool has to be able to ask.
 */
interface IRWAValuation is AggregatorV3Interface {
    /// @notice Unix timestamp at which the instrument redeems at par.
    /// @dev Zero means the instrument does not mature (an open-ended fund).
    function maturityDate() external view returns (uint64);

    /// @notice Par value per whole token, 8 decimals.
    function faceValue() external view returns (uint256);

    function isMatured() external view returns (bool);
}
