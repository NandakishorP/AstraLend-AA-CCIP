// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {CollateralStateMirror} from "../StateMirror/CollateralStateMirror.sol";
import {LoanManager} from "../GSM/LoanManager.sol";

interface IStateAggregator {
    function updateCollateralDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        CollateralStateMirror.CollateralDetailsOfUser
            memory collateralDetailsOfUser_
    ) external;

    function readCollateralDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256);

    function updateLoanDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId,
        LoanManager.LoanDetails memory loanDetails
    ) external;

    function updateDepositDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external;

    function readNumberOfLoanTakenPerToken(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256);

    function readDepositDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256);

    function readTotalLiquidityPerChainPerToken(
        uint256 chainId,
        uint64 tokenId
    ) external view returns (uint256);

    function readTotalLiquidityPerToken(
        uint64 tokenId
    ) external view returns (uint256);

    function updateLpTokensForAUser(address user, uint256 amount) external;

    function getLpTokensPerUserPerChain(
        uint256 chainId,
        address user
    ) external view returns (uint256);

    function getTotalLpTokensInAChain(
        uint64 chainId
    ) external view returns (uint256);

    function getTotalLpTokensInCirculation() external view returns (uint256);

    function getLpTokensPerUser(address user) external view returns (uint256);

    function getLpTokensPerUserPerChain(
        uint64 chainId,
        address user
    ) external view returns (uint256);

    function updateLpTokensPerUserPerChain(
        uint256 chainId,
        address user,
        uint256 amount
    ) external;

    function updateTotalLpTokensInAChain(
        uint256 chainId,
        uint256 amount
    ) external;

    function updateLpTokenInCirculation(uint256 amount) external;

    function updateBorrowerIndex(uint64 tokenId, uint256 value) external;

    function getBorrowerIndex(uint64 tokenId) external view returns (uint256);
}
