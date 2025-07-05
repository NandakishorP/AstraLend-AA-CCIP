// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";

contract LPTokenStateMirror is Ownable {
    mapping(address user => uint256 amount) private s_TotalLPTokenOwned;

    mapping(uint256 chainId => mapping(address user => uint256 amount))
        private s_LPTokenOwned;

    mapping(uint256 chainId => uint256 amount)
        private s_LPtokenInCirculationPerChain;

    uint256 private s_totalLPTokensInCirculation;

    constructor() Ownable(msg.sender) {}

    function updateLpTokensForAUser(
        address user,
        uint256 amount
    ) external onlyOwner {
        s_TotalLPTokenOwned[user] = amount;
    }

    function updateLpTokensPerUserPerChain(
        uint256 chainId,
        address user,
        uint256 amount
    ) external onlyOwner {
        s_LPTokenOwned[chainId][user] = amount;
    }

    function updateTotalLpTokensInAChain(
        uint256 chainId,
        uint256 amount
    ) external onlyOwner {
        s_LPtokenInCirculationPerChain[chainId] = amount;
    }

    function updateLpTokenInCirculation(uint256 amount) external onlyOwner {
        s_totalLPTokensInCirculation = amount;
    }

    function getLpTokensPerUser(
        address user
    ) external view onlyOwner returns (uint256) {
        return s_TotalLPTokenOwned[user];
    }

    function getLpTokensPerUserPerChain(
        uint64 chainId,
        address user
    ) external view onlyOwner returns (uint256) {
        return s_LPTokenOwned[chainId][user];
    }

    function getTotalLpTokensInAChain(
        uint64 chainId
    ) external view onlyOwner returns (uint256) {
        return s_LPtokenInCirculationPerChain[chainId];
    }

    function getTotalLpTokensInCirculation()
        external
        view
        onlyOwner
        returns (uint256)
    {
        return s_totalLPTokensInCirculation;
    }

    function totalLPTokensInCirculation()
        external
        view
        onlyOwner
        returns (uint256)
    {
        return
            s_LPtokenInCirculationPerChain[11155111] +
            s_LPtokenInCirculationPerChain[421614];
    }
}
