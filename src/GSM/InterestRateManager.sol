// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IInterestRateModel} from "../interfaces/IInterestRateModel.sol";

contract InterestRateManager is Ownable {
    IInterestRateModel interestRateModel;

    /// @notice Tracks the index representing the total interest factor for each token across all borrowers.
    /// @dev This index is used to calculate the compounded interest for each borrower of a specific token.
    /// Each time interest is accrued, this index is updated to reflect the cumulative interest growth.
    /// The individual borrower's interest can be calculated using the difference between the current index
    /// and the index at the time of borrowing.

    mapping(uint64 tokenId => uint256 borrowerIndexOfToken)
        public s_borrowerIndex;

    /// @notice Records the last timestamp when interest was accrued for each token.
    /// @dev This is used to determine how much time has passed since the last interest update for a specific token,
    /// which is essential for calculating how much new interest should be added to the borrower's debt.
    /// Interest accrual operations refer to this timestamp to keep interest calculations accurate and consistent.

    mapping(uint64 tokenId => uint256) public s_lastAccuralTime;

    constructor(address interestRateModelAddress_) Ownable(msg.sender) {
        interestRateModel = IInterestRateModel(interestRateModelAddress_);
    }

    function setInitalBorrowerIndex(uint64 tokenId) external onlyOwner {
        s_borrowerIndex[tokenId] = 1e18;
        s_lastAccuralTime[tokenId] = block.timestamp;
    }

    function _accuredInterest(uint64 tokenId) private onlyOwner {
        uint256 timeElapsed = block.timestamp - s_lastAccuralTime[tokenId];
        if (timeElapsed == 0) return;
        uint256 annualInterestRate = interestRateModel.getInterestRate(tokenId);
        uint256 ratePerSecond = annualInterestRate / 365 days;
        uint256 interestFactor = ratePerSecond * timeElapsed;
        s_borrowerIndex[tokenId] +=
            (s_borrowerIndex[tokenId] * interestFactor) /
            1e18;
        s_lastAccuralTime[tokenId] = block.timestamp;
    }

    function updateInterestRate(uint64 tokenId) external onlyOwner {
        _accuredInterest(tokenId);
    }

    function getBorrowerIndex(
        uint64 tokenId
    ) external view onlyOwner returns (uint256) {
        return s_borrowerIndex[tokenId];
    }
}
