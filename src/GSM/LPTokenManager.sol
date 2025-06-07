// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LPTokenManager is Ownable {
    mapping(address user => uint256 amount) private s_TotalLPTokenOwned;
    mapping(uint64 chainId => mapping(address user => uint256 amount))
        private s_LPTokenOwned;

    mapping(uint64 chainId => uint256 amount) private s_LPtokenInCirculation;

    uint256 s_totalLPTokensInCirculation;

    constructor() Ownable(msg.sender) {}

    function updateLpTokenInCirculation(
        uint64 chainId,
        address user,
        uint256 amount
    ) external {
        s_TotalLPTokenOwned[user] += amount;
        s_LPTokenOwned[chainId][user] += amount;
        s_LPtokenInCirculation[chainId] += amount;
        s_totalLPTokensInCirculation += amount;
    }

    function getLpTokensPerUser(address user) external view returns (uint256) {
        return s_TotalLPTokenOwned[user];
    }

    function getLpTokensPerUserPerChain(
        uint64 chainId,
        address user
    ) external view returns (uint256) {
        return s_LPTokenOwned[chainId][user];
    }

    function getTotalLpTokensInAChain(
        uint64 chainId
    ) external view returns (uint256) {
        return s_LPtokenInCirculation[chainId];
    }

    function getTotalLpTokensInCirculation() external view returns (uint256) {
        return s_totalLPTokensInCirculation;
    }

    function totalLPTokensInCirculation() external view returns (uint256) {
        return
            s_LPtokenInCirculation[11155111] + s_LPtokenInCirculation[421614];
    }
}
