pragma solidity ^0.8.20;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DepositStateMirror is Ownable {
    constructor() Ownable(msg.sender) {}

    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => uint256 amount)))
        private s_globalDespositDetailsOfUser;

    mapping(uint256 chainId => mapping(uint64 tokenId => uint256 amount))
        private s_globalLiquidityPerTokenPerChain;

    mapping(uint64 tokenId => uint256 amount) private s_globalLiquidityPerToken;

    function updateDepositDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external onlyOwner {
        s_globalDespositDetailsOfUser[chainId][user][tokenId] = amount;
        s_globalLiquidityPerTokenPerChain[chainId][tokenId] = amount;
        s_globalLiquidityPerToken[tokenId] += amount;
    }

    function readDepositDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view onlyOwner returns (uint256) {
        return s_globalDespositDetailsOfUser[chainId][user][tokenId];
    }

    function readTotalLiquidityPerChainPerToken(
        uint256 chainId,
        uint64 tokenId
    ) external view onlyOwner returns (uint256) {
        return s_globalLiquidityPerTokenPerChain[chainId][tokenId];
    }

    function readTotalLiquidityPerToken(
        uint64 tokenId
    ) external view onlyOwner returns (uint256) {
        return s_globalLiquidityPerToken[tokenId];
    }
}
