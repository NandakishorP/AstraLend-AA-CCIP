pragma solidity ^0.8.24;

import {IInterestRateModel} from "../interfaces/IInterestRateModel.sol";
import {ILendingPoolContract} from "../interfaces/ILendingPoolContract.sol";
import {IGlobalStateManager} from "../interfaces/IGlobalStateManager.sol";
import {InterestRateModelErrors} from "../errors/Errors.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "forge-std/console.sol";

contract InterestRateModel is IInterestRateModel, Ownable {

    ILendingPoolContract private lendingPoolContract;
    IGlobalStateManager private GSM;

    constructor() Ownable(msg.sender) {}

    function setLendingPoolContractAndGSM(
        address _lendingPool,
        address gsm
    ) external onlyOwner {
        lendingPoolContract = ILendingPoolContract(_lendingPool);
        GSM = IGlobalStateManager(gsm);
    }

    modifier isTokenApprovedByTheContract(uint64 tokenId) {
        if (address(lendingPoolContract) == address(0)) {
            revert InterestRateModelErrors
                .InterestRateModel__TokenNotSupported();
        }
        if (lendingPoolContract.getPriceFeedAddress(tokenId) == address(0)) {
            revert InterestRateModelErrors
                .InterestRateModel__TokenNotSupported();
        }
        _;
    }



    uint256 private constant PRECISION = 1e18;


    uint256 public baseInterestRate = 5e16;


    uint256 public maxInterestRate = 100e16;


    uint256 public kink = 70e16;

    function getUtilizationRatio(
        uint64 tokenId
    ) external view isTokenApprovedByTheContract(tokenId) returns (uint256) {
        return _calculateUtilizationRatio(tokenId);
    }

    function getInterestRate(
        uint64 tokenId
    ) external view isTokenApprovedByTheContract(tokenId) returns (uint256) {
        return _calculateInterestRate(tokenId);
    }
    function _calculateUtilizationRatio(
        uint64 assetClassId
    ) internal view returns (uint256 utilizationRatio) {
        uint256 liquidityPerAssetClass = GSM.getTotalLiquidityPerToken(
            assetClassId
        );
        uint256 amountBorrowedPerAssetClass = GSM.getTotalCollateralPerToken(
            assetClassId
        );
        if (liquidityPerAssetClass == 0 || liquidityPerAssetClass == 0) {
            return 0;
        }
        utilizationRatio =
            (amountBorrowedPerAssetClass * PRECISION) /
            (liquidityPerAssetClass + amountBorrowedPerAssetClass);
    }
    function _calculateInterestRate(
        uint64 tokenId
    ) public view returns (uint256) {
        uint256 utilizationRatio = _calculateUtilizationRatio(tokenId);
        uint256 interestRate;
        if (utilizationRatio < kink) {
            interestRate =
                baseInterestRate +
                (((maxInterestRate - baseInterestRate) * utilizationRatio) /
                    kink);
        } else {
            interestRate =
                maxInterestRate +
                ((maxInterestRate * (utilizationRatio - kink)) /
                    (PRECISION - kink));
        }
        return interestRate;
    }
}
