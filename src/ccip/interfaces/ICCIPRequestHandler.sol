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

    function repayLoanDetailsOfUser(
        LendingPoolContract.CrossChainPayLoad memory actionPayLoad
    ) external;

    function updateBorrowLoanDetailsOfUser(
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

    function updateDepositDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external;

    function mirrorUpdateOfTheUserDeposit(
        address receiver,
        uint256 chainId_,
        address user_,
        uint64 tokenId,
        uint64 destinationChainSelector
    ) external;

    function updateLPTokensInCirculation(
        uint256 chainId,
        address user,
        uint256 amount
    ) external;

    function updateWithdrawDepositDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external;

    function setGSMAddress(address gsm) external;
}
