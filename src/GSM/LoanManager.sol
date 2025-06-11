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
    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => mapping(uint256 loanId => LoanDetails))))
        private s_loanDetails;
    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => uint256 totalNumberOfLoanTaken)))
        private s_numberOfLoansTaken;
    mapping(address user => mapping(uint64 tokenId => bool))
        private s_isBorrower;

    function updateLoanDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId,
        LoanDetails memory loanDetails
    ) external onlyOwner {
        s_loanDetails[chainId][user][tokenId][loanId] = loanDetails;
    }

    function updateLoanTakers(
        address user,
        uint64 tokenId,
        bool status
    ) external onlyOwner {
        s_isBorrower[user][tokenId] = status;
    }

    function updateNumberOfLoansTaken(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanNumber
    ) external onlyOwner {
        s_numberOfLoansTaken[chainId][user][tokenId] = loanNumber;
    }

    function getLoanDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId
    ) external view onlyOwner returns (LoanDetails memory) {
        return s_loanDetails[chainId][user][tokenId][loanId];
    }

    function getNumberOfLoansTakenPerToken(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view onlyOwner returns (uint256) {
        return s_numberOfLoansTaken[chainId][user][tokenId];
    }
}
