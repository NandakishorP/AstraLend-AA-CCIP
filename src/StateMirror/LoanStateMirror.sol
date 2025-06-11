// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {LoanManager} from "../GSM/LoanManager.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LoanStateMirror is Ownable {
    constructor() Ownable(msg.sender) {}

    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => mapping(uint256 loanId => LoanManager.LoanDetails))))
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
        LoanManager.LoanDetails memory loanDetails
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
    ) external view onlyOwner returns (LoanManager.LoanDetails memory) {
        return s_loanDetails[chainId][user][tokenId][loanId];
    }

    function getNumberOfLoansTakenPerToken(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view onlyOwner returns (uint256) {
        return s_numberOfLoansTaken[chainId][user][tokenId];
    }

    function getLoanStatusOfUserInAToken(
        address user,
        uint64 tokenId
    ) external view onlyOwner returns (bool) {
        return s_isBorrower[user][tokenId];
    }
}
