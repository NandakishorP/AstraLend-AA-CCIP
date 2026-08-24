pragma solidity ^0.8.20;
import {LoanManager} from "../GSM/LoanManager.sol";

interface IGlobalStateManager {

    function updateDepositCollateralOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external;

    function updateWithdrawCollateralOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external;

    function getUserCollateralDetails(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256);

    function getTotalCollateralDetails(
        uint256 chainId,
        uint64 tokenId
    ) external view returns (uint256);

    function mirrorUpdateOfTheUserCollateral(
        address receiver,
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint64 destinationChainSelector
    ) external;

    function updateBorrowLoanDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        LoanManager.LoanDetails memory loanDetails
    ) external;

    function repayLoanDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        LoanManager.LoanDetails memory loanDetails
    ) external;

    function readLoanDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId
    ) external view returns (LoanManager.LoanDetails memory);

    function readNumberOfLoanTakenPerToken(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256);

    function mirrorUpdateOfTheUserLoan(
        address receiver,
        uint256 chainId_,
        address user_,
        uint64 tokenId,
        uint256 loanId,
        uint64 destinationChainSelector
    ) external;

    function updateDepositDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external;

    function readDepositDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256);

    function readTotalLiquidityPerChainPerToken(
        uint256 chainId,
        uint64 tokenId
    ) external view returns (uint256);

    function readTotalLiquidityPerToken(
        uint64 tokenId
    ) external view returns (uint256);

    function mirrorUpdateOfTheUserDeposit(
        address receiver,
        uint256 chainId_,
        address user_,
        uint64 tokenId,
        uint64 destinationChainSelector
    ) external;

    function getLpTokensPerUser(address user) external view returns (uint256);

    function getLpTokensPerUserPerChain(
        uint256 chainId,
        address user
    ) external view returns (uint256);

    function getTotalLpTokensInAChain(
        uint256 chainId
    ) external view returns (uint256);

    function getTotalLpTokensInCirculation() external view returns (uint256);

    function totalLPTokensInCirculation() external view returns (uint256);

    function updateLPTokenInCirculation(
        uint256 chainId,
        address user,
        uint256 amount
    ) external;

    function updateWithDrawDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external;

    function getBorrowerIndex(uint64 tokenId) external returns (uint256);

    function getTotalCollateralPerToken(
        uint64 tokenId
    ) external view returns (uint256);

    function getTotalLiquidityPerToken(
        uint64 tokenId
    ) external view returns (uint256);

    function getTotalBorrowedPerToken(
        uint64 tokenId
    ) external view returns (uint256);
}
