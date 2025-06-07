// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CollateralStateMirror} from "./CollateralStateMirror.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";

contract StateAggregator is Ownable {
    error StateAggregator__InvalidSender();

    CollateralStateMirror collateralStateMirror;
    mapping(address => bool) private s_isAuthorizedToUpdate;
    mapping(address => bool) private s_isAuthorizedToRead;
    modifier onlyCCIPHandlersCanCall() {
        if (!s_isAuthorizedToUpdate[msg.sender]) {
            revert StateAggregator__InvalidSender();
        }
        _;
    }

    modifier onlyAuthorizedReadersCanCall() {
        if (!s_isAuthorizedToRead[msg.sender]) {
            revert StateAggregator__InvalidSender();
        }
        _;
    }

    function setAuthorizedUpdators(
        address caller,
        bool status
    ) external onlyOwner {
        s_isAuthorizedToUpdate[caller] = status;
    }

    function setAuthorizedReadors(
        address caller,
        bool status
    ) external onlyOwner {
        s_isAuthorizedToRead[caller] = status;
    }

    constructor() Ownable(msg.sender) {
        collateralStateMirror = new CollateralStateMirror();
    }

    // collateral managment

    function updateCollateralDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        CollateralStateMirror.CollateralDetailsOfUser
            memory collateralDetailsOfUser_
    ) external onlyCCIPHandlersCanCall {
        console.log(collateralDetailsOfUser_.amount);
        collateralStateMirror.updateCollateralDetaiilsOfUser(
            chainId,
            user,
            tokenId,
            collateralDetailsOfUser_
        );
    }

    function readCollateralDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view onlyAuthorizedReadersCanCall returns (uint256) {
        return
            collateralStateMirror
                .readCollateralDetailsOfUser(chainId, user, tokenId)
                .amount;
    }
}
