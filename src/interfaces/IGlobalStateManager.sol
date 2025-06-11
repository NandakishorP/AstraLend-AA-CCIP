// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {LoanManager} from "../GSM/LoanManager.sol";

interface IGlobalStateManager {
    // COLLATERAL SECTION

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

    function updateLoanDetailsOfUser(
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
}
