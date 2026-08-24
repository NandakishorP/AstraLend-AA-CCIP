pragma solidity ^0.8.20;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IInterestRateModel} from "../interfaces/IInterestRateModel.sol";

contract InterestRateManager is Ownable {
    IInterestRateModel interestRateModel;


    mapping(uint64 tokenId => uint256 borrowerIndexOfToken)
        public s_borrowerIndex;


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
