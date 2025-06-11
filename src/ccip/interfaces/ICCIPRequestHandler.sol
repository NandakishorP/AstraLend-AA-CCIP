// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {LendingPoolContract} from "../../LendingPoolContract.sol";

interface ICCIPRequestHandler {
    function updateDepositCollateralDetailsOfUser(
        LendingPoolContract.CrossChainPayLoad memory actionPayLoad
    ) external;

    function updateWithdrawDepositCollateralDetailsOfUser(
        LendingPoolContract.CrossChainPayLoad memory actionPayLoad
    ) external;

    function updateLoanDetailsOfUser(
        LendingPoolContract.CrossChainPayLoad memory actionPayLoad
    ) external;

    function updateCollateralStateMirror(
        address receiver,
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint64 destinationChainSelector
    ) external;

    function updateLoanStateMirror(
        address receiver,
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId,
        uint64 destinationChainSelector
    ) external;
}
