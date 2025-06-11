// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LoanManager is Ownable {
    constructor() Ownable(msg.sender) {}

    struct LoanDetails {
        address token; // ───────────────────────────────╮ ERC20 token address borrowed by the user
        uint256 amountBorrowedInUSDT; //                 │ Amount borrowed, denominated in USDT (smallest unit: 6 decimals)
        uint256 principalAmount; //                      | The principal amount taken for further reference
        uint256 collateralUsed; //                       │ Collateral amount locked by the user (in collateral token units)
        uint256 collateralChainId; //                     | Chain in which the collateral is locked
        uint256 lastUpdate; //                           │ Timestamp of the last update to the loan state
        address asset; //                                | Address of the token in which user take the loan
        uint256 userBorrowIndex; //                      | The borrowerIndex of the contract when the user made any last update on the loan
        uint256 interestPaid; //                         | The total interest paid by the user over time
        uint256 liquidationPoint; //                     | The liquidation point for the loan, calculated as LTV * collateral amount
        uint256 dueDate; //                              |   Timestamp when the loan repayment is due
        uint256 loanId; //  ─────────────────────────────╯
        uint8 penaltyCount; // ───────────────────────────────╮ Penalty count  after due date (limit is 2)
        bool isLiquidated; // ────────────────────────────────╯ True if the loan has been liquidated due to default
    }
    /// @notice Stores loan details per chain, user, token, and loan ID.
    /// @dev Mapping structure: chainId → user → tokenId → loanId → LoanDetails
    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => mapping(uint256 loanId => LoanDetails))))
        private s_loanDetails;

    /// @notice Tracks the number of loans a user has taken for a specific token on a specific chain.
    /// @dev Mapping structure: chainId → user → tokenId → totalNumberOfLoanTaken
    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => uint256 totalNumberOfLoanTaken)))
        private s_numberOfLoansTaken;

    /// @notice Indicates whether a user is currently a borrower for a specific token.
    /// @dev Mapping structure: user → tokenId → bool
    mapping(address user => mapping(uint64 tokenId => bool))
        private s_isBorrower;

    /// @notice Updates the loan details for a user on a specific chain and token.
    /// @dev Only callable by the contract owner.
    /// @param chainId The chain ID on which the loan was taken.
    /// @param user The address of the user who took the loan.
    /// @param tokenId The token ID associated with the loan.
    /// @param loanId The unique identifier for the loan.
    /// @param loanDetails A struct containing the full loan information.
    function updateLoanDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId,
        LoanDetails memory loanDetails
    ) external onlyOwner {
        s_loanDetails[chainId][user][tokenId][loanId] = loanDetails;
    }

    /// @notice Updates the borrower status of a user for a given token.
    /// @dev Only callable by the contract owner.
    /// @param user The address of the user.
    /// @param tokenId The token ID to mark borrowing status for.
    /// @param status Boolean indicating whether the user is a borrower.

    function updateLoanTakers(
        address user,
        uint64 tokenId,
        bool status
    ) external onlyOwner {
        s_isBorrower[user][tokenId] = status;
    }

    /// @notice Sets the total number of loans taken by a user for a specific token and chain.
    /// @dev Only callable by the contract owner.
    /// @param chainId The chain ID where the loans were issued.
    /// @param user The address of the user.
    /// @param tokenId The token associated with the loans.
    /// @param loanNumber The number of loans to set for the user.

    function updateNumberOfLoansTaken(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanNumber
    ) external onlyOwner {
        s_numberOfLoansTaken[chainId][user][tokenId] = loanNumber;
    }

    /// @notice Fetches the details of a specific loan taken by a user on a given chain and token.
    /// @dev Only callable by the contract owner.
    /// @param chainId The chain ID of the loan.
    /// @param user The user address.
    /// @param tokenId The token ID associated with the loan.
    /// @param loanId The ID of the loan to retrieve.
    /// @return A LoanDetails struct containing the loan data.

    function getLoanDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId
    ) external view onlyOwner returns (LoanDetails memory) {
        return s_loanDetails[chainId][user][tokenId][loanId];
    }

    /// @notice Returns the total number of loans taken by a user for a specific token on a given chain.
    /// @dev Only callable by the contract owner.
    /// @param chainId The chain ID where the loans were taken.
    /// @param user The address of the user.
    /// @param tokenId The token ID of interest.
    /// @return The total number of loans recorded for the user.

    function getNumberOfLoansTakenPerToken(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view onlyOwner returns (uint256) {
        return s_numberOfLoansTaken[chainId][user][tokenId];
    }
}
