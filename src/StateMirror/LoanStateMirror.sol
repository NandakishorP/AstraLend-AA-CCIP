// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {LoanManager} from "../GSM/LoanManager.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Loan State Mirror
/// @notice Mirrors loan-related information for users from other chains.
/// @dev Only the contract owner can update or read the loan data.
contract LoanStateMirror is Ownable {
    constructor() Ownable(msg.sender) {}

    /// @notice Loan details of a user per chain, token, and loan ID.
    /// @dev Nested mapping: chainId → user → tokenId → loanId → LoanDetails.
    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => mapping(uint256 loanId => LoanManager.LoanDetails))))
        private s_loanDetails;

    /// @notice Tracks the number of loans taken by a user for each token on each chain.
    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => uint256 totalNumberOfLoanTaken)))
        private s_numberOfLoansTaken;

    /// @notice Indicates if a user has ever borrowed using a particular token.
    mapping(address user => mapping(uint64 tokenId => bool))
        private s_isBorrower;

    /// @notice Updates the loan details for a given user, token, and loan ID on a specific chain.
    /// @dev Callable only by the owner (e.g., cross-chain coordinator).
    /// @param chainId Chain ID from which the loan originated.
    /// @param user Address of the borrower.
    /// @param tokenId Token used for the loan.
    /// @param loanId Unique identifier for the loan.
    /// @param loanDetails Struct containing all loan-related information.

    function updateLoanDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId,
        LoanManager.LoanDetails memory loanDetails
    ) external onlyOwner {
        s_loanDetails[chainId][user][tokenId][loanId] = loanDetails;
    }

    /// @notice Updates whether the given user is a borrower for a specific token.
    /// @param user The user’s address.
    /// @param tokenId The token identifier.
    /// @param status `true` if the user is a borrower, otherwise `false`.
    function updateLoanTakers(
        address user,
        uint64 tokenId,
        bool status
    ) external onlyOwner {
        s_isBorrower[user][tokenId] = status;
    }

    /// @notice Updates the total number of loans taken by a user for a token on a given chain.
    /// @param chainId Originating chain ID.
    /// @param user The user’s address.
    /// @param tokenId The token identifier.
    /// @param loanNumber Total number of loans to update.

    function updateNumberOfLoansTaken(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanNumber
    ) external onlyOwner {
        s_numberOfLoansTaken[chainId][user][tokenId] = loanNumber;
    }

    /// @notice Fetches the loan details for a user for a specific token and loan ID.
    /// @dev Restricted to the owner only.
    /// @param chainId Chain from which the loan originated.
    /// @param user Address of the borrower.
    /// @param tokenId Token involved in the loan.
    /// @param loanId Unique identifier for the loan.
    /// @return The `LoanManager.LoanDetails` struct.

    function getLoanDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId
    ) external view onlyOwner returns (LoanManager.LoanDetails memory) {
        return s_loanDetails[chainId][user][tokenId][loanId];
    }

    /// @notice Returns the number of loans a user has taken for a specific token on a specific chain.
    /// @param chainId The originating chain ID.
    /// @param user The user’s address.
    /// @param tokenId The token identifier.
    /// @return Number of loans taken.

    function getNumberOfLoansTakenPerToken(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view onlyOwner returns (uint256) {
        return s_numberOfLoansTaken[chainId][user][tokenId];
    }

    /// @notice Checks if a user has ever borrowed using a given token.
    /// @param user The user’s address.
    /// @param tokenId Token identifier.
    /// @return `true` if the user is a borrower, otherwise `false`.
    function getLoanStatusOfUserInAToken(
        address user,
        uint64 tokenId
    ) external view onlyOwner returns (bool) {
        return s_isBorrower[user][tokenId];
    }
}
