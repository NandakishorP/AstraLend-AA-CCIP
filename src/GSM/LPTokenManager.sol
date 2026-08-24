pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LPTokenManager is Ownable {
    mapping(address user => uint256 amount) private s_TotalLPTokenOwned;

    mapping(uint256 chainId => mapping(address user => uint256 amount))
        private s_LPTokenOwned;

    mapping(uint256 chainId => uint256 amount) private s_LPtokenInCirculation;

    uint256 private s_totalLPTokensInCirculation;

    constructor() Ownable(msg.sender) {}

    function updateLpTokenInCirculation(
        uint256 chainId,
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
        uint256 chainId,
        address user
    ) external view returns (uint256) {
        return s_LPTokenOwned[chainId][user];
    }


    function getTotalLpTokensInAChain(
        uint256 chainId
    ) external view returns (uint256) {
        return s_LPtokenInCirculation[chainId];
    }

    function getTotalLpTokensInCirculation() external view returns (uint256) {
        return s_totalLPTokensInCirculation;
    }
}
