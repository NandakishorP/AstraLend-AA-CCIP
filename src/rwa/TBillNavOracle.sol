// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRWAValuation} from "./interfaces/IRWAValuation.sol";

/**
 * @title TBillNavOracle
 * @notice Values a Treasury bill by accretion rather than by attestation.
 *
 * @dev A bill has no price to report. It is bought at a discount and redeems at
 *      par on a known date, so its value is a deterministic function of time,
 *      not a market observation. This contract computes it.
 *
 *      That has a property worth stating plainly: there is no oracle to trust
 *      and no staleness to check. `updatedAt` is always `block.timestamp`
 *      because the value is derived on read. Every other RWA design has to
 *      answer "what if the NAV feed goes stale"; for a bill the question does
 *      not arise.
 *
 *      Accretion is linear rather than yield-curve discounted. For a 91-day
 *      bill the divergence from the exact discounted value is a few basis
 *      points, which is far inside the haircut, and the simplicity is worth
 *      more than the precision here.
 *
 *      Prices carry 8 decimals to match Chainlink feeds, since the pool scales
 *      by ADDITIONAL_PRICEFEED_PRECISION = 1e10 on the way to 18.
 */
contract TBillNavOracle is IRWAValuation {
    error TBillNav__BadTenor(uint64 issueDate, uint64 maturityDate);
    error TBillNav__FaceBelowIssue(uint256 issuePrice, uint256 faceValue);

    uint8 private constant DECIMALS = 8;
    uint256 private constant VERSION = 1;

    uint256 private immutable i_issuePrice;
    uint256 private immutable i_faceValue;
    uint64 private immutable i_issueDate;
    uint64 private immutable i_maturityDate;
    string private s_description;

    constructor(
        string memory description_,
        uint256 issuePrice,
        uint256 faceValue_,
        uint64 issueDate,
        uint64 maturityDate_
    ) {
        if (maturityDate_ <= issueDate) revert TBillNav__BadTenor(issueDate, maturityDate_);
        if (faceValue_ < issuePrice) revert TBillNav__FaceBelowIssue(issuePrice, faceValue_);

        s_description = description_;
        i_issuePrice = issuePrice;
        i_faceValue = faceValue_;
        i_issueDate = issueDate;
        i_maturityDate = maturityDate_;
    }

    /// @dev Flat at issue price before issuance and at par after maturity, so
    ///      the curve is defined for every timestamp a caller might pass.
    function _navAt(uint256 timestamp) internal view returns (uint256) {
        if (timestamp <= i_issueDate) return i_issuePrice;
        if (timestamp >= i_maturityDate) return i_faceValue;

        uint256 elapsed = timestamp - i_issueDate;
        uint256 tenor = i_maturityDate - i_issueDate;
        return i_issuePrice + ((i_faceValue - i_issuePrice) * elapsed) / tenor;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, int256(_navAt(block.timestamp)), i_issueDate, block.timestamp, 1);
    }

    /// @dev Historical rounds are exact rather than recorded — the accretion
    ///      curve is known in advance, so any past value can be recomputed.
    function getRoundData(uint80 roundId_)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (roundId_, int256(_navAt(block.timestamp)), i_issueDate, block.timestamp, roundId_);
    }

    function navAt(uint256 timestamp) external view returns (uint256) {
        return _navAt(timestamp);
    }

    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    function version() external pure returns (uint256) {
        return VERSION;
    }

    function description() external view returns (string memory) {
        return s_description;
    }

    function maturityDate() external view returns (uint64) {
        return i_maturityDate;
    }

    function faceValue() external view returns (uint256) {
        return i_faceValue;
    }

    function issuePrice() external view returns (uint256) {
        return i_issuePrice;
    }

    function issueDate() external view returns (uint64) {
        return i_issueDate;
    }

    function isMatured() external view returns (bool) {
        return block.timestamp >= i_maturityDate;
    }
}
