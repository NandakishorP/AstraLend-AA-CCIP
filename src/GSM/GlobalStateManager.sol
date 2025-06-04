// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GlobalStateManagerErrors} from "../errors/Errors.sol";
import {IGlobalStateManager} from "../interfaces/IGlobalStateManager.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract GlobalStateManager is IGlobalStateManager, Ownable {
    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => uint256 amount)))
        private s_globalCollateralDetailsForAUser;

    mapping(uint256 chainId => mapping(uint64 tokenID => uint256 amount))
        private s_totalCollateralDepositedInTheChain;

    mapping(address caller => bool) private s_isAllowedToCall;

    constructor() Ownable(msg.sender) {}

    // only the lending pool contract of the main chain and the cross chain senders
    // of the other chains can call this state manager contract
    // this need to be implemented

    modifier isChainRegesitedToCall() {
        if (!s_isAllowedToCall[msg.sender]) {
            revert GlobalStateManagerErrors.GlobalStateManager__InvalidSender();
        }
        _;
    }

    function setAllowedChains(address sender) external onlyOwner {
        if (sender != address(0)) {
            s_isAllowedToCall[sender] = true;
        }
    }

    function updateCollateralDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external isChainRegesitedToCall {
        s_globalCollateralDetailsForAUser[chainId][user][tokenId] += amount;
        s_totalCollateralDepositedInTheChain[chainId][tokenId] += amount;
    }

    function getUserCollateralDetails(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view isChainRegesitedToCall returns (uint256) {
        return s_globalCollateralDetailsForAUser[chainId][user][tokenId];
    }
}
