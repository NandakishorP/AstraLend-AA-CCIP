// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CollateralStateMirror} from "./CollateralStateMirror.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";
import {LoanManager} from "../GSM/LoanManager.sol";
import {LoanStateMirror} from "./LoanStateMirror.sol";
import {DepositStateMirror} from "./DepositStateMirror.sol";
import {LPTokenStateMirror} from "./LPTokenStateMirror.sol";

/**
 * @title StateAggregator
 * @author Nandakishor
 * @notice Aggregates and synchronizes user collateral and loan states across chains.
 * @dev This contract acts as a bridge to update and read off-chain-synced data related to user collateral and loan positions.
 *      It maintains secure, permissioned access using `onlyOwner`, `onlyCCIPHandlersCanCall`, and `onlyAuthorizedReadersCanCall`.
 *
 * Functional Overview:
 * - **Collateral Management**:
 *      - Updates and reads user collateral information from remote chains via the `CollateralStateMirror`.
 * - **Loan Management**:
 *      - Updates and reads loan data for users across chains via the `LoanStateMirror`.
 *      - Manages borrow status, loan count, and full loan struct details.
 *
 * Access Control:
 * - `onlyOwner`: Used to configure authorized updaters and readers.
 * - `onlyCCIPHandlersCanCall`: Restricts write operations to designated CCIP bridge/message handler addresses.
 * - `onlyAuthorizedReadersCanCall`: Restricts read operations to whitelisted consumer contracts.
 *
 * Security:
 * - Only the contract deployer (owner) can assign reader/updater permissions.
 * - State is stored in separate mirror contracts to isolate logic and storage.
 *
 * Intended Use:
 * - Called by CCIP handlers or cross-chain systems to synchronize state.
 * - Called by trusted contracts (e.g., frontend relay readers or verification contracts) to fetch mirrored data.
 */

contract StateAggregator is Ownable {
    error StateAggregator__InvalidSender();

    CollateralStateMirror collateralStateMirror;

    LoanStateMirror loanStateMirror;

    DepositStateMirror depositStateMirror;

    LPTokenStateMirror lpTokenStateMirror;

    mapping(address => bool) private s_isAuthorizedToUpdate;

    mapping(address => bool) private s_isAuthorizedToRead;

    mapping(uint64 tokenId => uint256 amount) private s_borrowerIndex;

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

    constructor() Ownable(msg.sender) {
        collateralStateMirror = new CollateralStateMirror();

        loanStateMirror = new LoanStateMirror();

        depositStateMirror = new DepositStateMirror();

        lpTokenStateMirror = new LPTokenStateMirror();
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

    function updateBorrowerIndex(
        uint64 tokenId,
        uint256 value
    ) external onlyCCIPHandlersCanCall {
        s_borrowerIndex[tokenId] = value;
    }

    function getBorrowerIndex(uint64 tokenId) external view returns (uint256) {
        return s_borrowerIndex[tokenId];
    }

    // collateral managment

    function updateCollateralDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        CollateralStateMirror.CollateralDetailsOfUser
            memory collateralDetailsOfUser_
    ) external onlyCCIPHandlersCanCall {
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

    //  LOAN MANAGMENT

    function updateLoanDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId,
        LoanManager.LoanDetails memory loanDetails
    ) external onlyCCIPHandlersCanCall {
        loanStateMirror.updateLoanDetailsOfUser(
            chainId,
            user,
            tokenId,
            loanId,
            loanDetails
        );

        loanStateMirror.updateNumberOfLoansTaken(
            chainId,
            user,
            tokenId,
            loanId
        );
    }

    function readNumberOfLoanTakenPerToken(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256) {
        return
            loanStateMirror.getNumberOfLoansTakenPerToken(
                chainId,
                user,
                tokenId
            );
    }

    function readLoanDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId
    )
        external
        view
        onlyAuthorizedReadersCanCall
        returns (LoanManager.LoanDetails memory)
    {
        return
            loanStateMirror.getLoanDetailsOfUser(
                chainId,
                user,
                tokenId,
                loanId
            );
    }

    function updateLoanTakers(
        address user,
        uint64 tokenId,
        bool status
    ) external onlyCCIPHandlersCanCall {
        loanStateMirror.updateLoanTakers(user, tokenId, status);
    }

    function getLoanTakerStatus(
        address user,
        uint64 tokenId
    ) external view onlyAuthorizedReadersCanCall returns (bool) {
        return loanStateMirror.getLoanStatusOfUserInAToken(user, tokenId);
    }

    // DEPOSIT FUNCTIONS

    function updateDepositDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external onlyCCIPHandlersCanCall {
        depositStateMirror.updateDepositDetailsOfUser(
            chainId,
            user,
            tokenId,
            amount
        );
    }

    function readDepositDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256) {
        return
            depositStateMirror.readDepositDetailsOfUser(chainId, user, tokenId);
    }

    function readTotalLiquidityPerChainPerToken(
        uint256 chainId,
        uint64 tokenId
    ) external view returns (uint256) {
        return
            depositStateMirror.readTotalLiquidityPerChainPerToken(
                chainId,
                tokenId
            );
    }

    function readTotalLiquidityPerToken(
        uint64 tokenId
    ) external view returns (uint256) {
        return depositStateMirror.readTotalLiquidityPerToken(tokenId);
    }

    // LP TOKEN

    // visibility is pending

    function updateLpTokensForAUser(address user, uint256 amount) external {
        lpTokenStateMirror.updateLpTokensForAUser(user, amount);
    }

    function getLpTokensPerUser(address user) external view returns (uint256) {
        return lpTokenStateMirror.getLpTokensPerUser(user);
    }

    function getLpTokensPerUserPerChain(
        uint64 chainId,
        address user
    ) external view returns (uint256) {
        return lpTokenStateMirror.getLpTokensPerUserPerChain(chainId, user);
    }

    function updateLpTokensPerUserPerChain(
        uint256 chainId,
        address user,
        uint256 amount
    ) external {
        lpTokenStateMirror.updateLpTokensPerUserPerChain(chainId, user, amount);
    }

    function updateTotalLpTokensInAChain(
        uint256 chainId,
        uint256 amount
    ) external {
        lpTokenStateMirror.updateTotalLpTokensInAChain(chainId, amount);
    }

    function updateLpTokenInCirculation(uint256 amount) external {
        lpTokenStateMirror.updateLpTokenInCirculation(amount);
    }

    function getTotalLpTokensInAChain(
        uint64 chainId
    ) external view returns (uint256) {
        return lpTokenStateMirror.getTotalLpTokensInAChain(chainId);
    }

    function getTotalLpTokensInCirculation() external view returns (uint256) {
        return lpTokenStateMirror.getTotalLpTokensInCirculation();
    }

    function totalLPTokensInCirculation() external view returns (uint256) {
        return lpTokenStateMirror.totalLPTokensInCirculation();
    }
}
