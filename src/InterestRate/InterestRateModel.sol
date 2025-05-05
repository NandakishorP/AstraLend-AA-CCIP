// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IInterestRateModel} from "../interfaces/IInterestRateModel.sol";
import {ILendingPoolContract} from "../interfaces/ILendingPoolContract.sol";
import {InterestRateModelErrors} from "../errors/Errors.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "forge-std/console.sol";

contract InterestRateModel is IInterestRateModel, Ownable {
    /// ERRORS

    ILendingPoolContract private lendingPoolContract;

    constructor() Ownable(msg.sender) {}

    function setLendingPoolContract(address _lendingPool) external onlyOwner {
        lendingPoolContract = ILendingPoolContract(_lendingPool);
    }

    modifier isTokenApprovedByTheContract(address token) {
        if (address(lendingPoolContract) == address(0)) {
            revert InterestRateModelErrors
                .InterestRateModel__TokenNotSupported();
        }
        if (lendingPoolContract.getPriceFeedAddress(token) == address(0)) {
            revert InterestRateModelErrors
                .InterestRateModel__TokenNotSupported();
        }
        _;
    }

    /// @dev this prevent the user from depositing money from chains that is not supported on this contract

    /// @dev The precision factor used for calculations involving token amounts or decimals
    /// @notice This constant defines the precision (1e18) for scaling values to match token precision or to avoid precision loss

    uint256 private constant PRECISION = 1e18;

    /// @notice The minimum interest rate applied when utilization is low (5% annualized).

    uint256 public baseInterestRate = 5e16;

    /// @notice The maximum interest rate applied after utilization exceeds the kink (50% annualized).

    uint256 public maxInterestRate = 50e16;

    /// @notice The utilization point (70%) at which the interest rate model shifts from linear to higher slope.

    uint256 public kink = 70e16;

    /**
     * @notice Returns the current utilization ratio for a specific token.
     * @dev Utilization ratio is calculated as the total borrowed amount
     * divided by the total liquidity available for the token.
     * @param token The address of the token to query.
     * @return The utilization ratio scaled by a precision factor.
     */

    function getUtilizationRatio(
        address token
    ) external view isTokenApprovedByTheContract(token) returns (uint256) {
        return _calculateUtilizationRatio(token);
    }

    /**
     * @notice Returns the current interest rate for borrowing a specific token.
     * @dev The interest rate is determined based on the utilization ratio and
     * adjusts dynamically using a kink-based model.
     * @param token The address of the token to query.
     * @return The annual interest rate scaled by a precision factor.
     */

    function getInterestRate(
        address token
    ) external view isTokenApprovedByTheContract(token) returns (uint256) {
        return _calculateInterestRate(token);
    }

    /**
     * @notice Calculates the utilization ratio of a given asset class.
     * @dev The utilization ratio is determined by dividing the total amount borrowed by the liquidity available for that asset class.
     * @param assetClass The address of the asset class (e.g., a specific token or collateral type).
     * @return utilizationRatio The calculated utilization ratio (scaled by PRECISION).
     */

    function _calculateUtilizationRatio(
        address assetClass
    ) internal view returns (uint256 utilizationRatio) {
        uint256 liquidityPerAssetClass = lendingPoolContract
            .getTotalLiquidityPerToken(assetClass);
        uint256 amountBorrowedPerAssetClass = lendingPoolContract
            .getTotalBorroweedForAToken(assetClass);
        if (liquidityPerAssetClass == 0) {
            return 0;
        }

        utilizationRatio =
            (amountBorrowedPerAssetClass * PRECISION) /
            liquidityPerAssetClass;
    }

    // calculating the interest rate
    /**
     * @notice Calculates the interest rate for a given token based on its utilization ratio.
     * @dev The interest rate is dynamically adjusted based on the utilization ratio of the token.
     * If the utilization ratio is below a defined threshold (`kink`), the interest rate increases gradually from a base rate to a maximum rate.
     * If the utilization ratio exceeds the `kink`, the interest rate increases more steeply towards the maximum interest rate.
     *
     * This function uses two main parameters:
     * - `baseInterestRate`: The starting interest rate when utilization is low.
     * - `maxInterestRate`: The maximum interest rate that can be reached when utilization exceeds the kink.
     *
     * The function calculates the `utilizationRatio` first, and then uses it to determine the appropriate interest rate based on the following logic:
     * 1. If the utilization ratio is below `kink`, the rate is a linear function of the utilization ratio.
     * 2. If the utilization ratio exceeds `kink`, the rate increases sharply as the utilization ratio rises.
     *
     * @param token The address of the token for which the interest rate is being calculated.
     * @return interestRate The calculated interest rate, scaled by the precision factor.
     */

    function _calculateInterestRate(
        address token
    ) public view returns (uint256) {
        uint256 utilizationRatio = _calculateUtilizationRatio(token);
        uint256 interestRate;
        if (utilizationRatio < kink) {
            interestRate =
                baseInterestRate +
                ((maxInterestRate - baseInterestRate) * utilizationRatio) /
                kink;
        } else {
            interestRate =
                maxInterestRate +
                ((maxInterestRate * (utilizationRatio - kink)) /
                    (PRECISION - kink));
        }

        return interestRate;
    }
}
