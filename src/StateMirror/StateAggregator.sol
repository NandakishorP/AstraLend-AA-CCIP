// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CollateralStateMirror} from "./CollateralStateMirror.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";
import {LoanManager} from "../GSM/LoanManager.sol";
import {LoanStateMirror} from "./LoanStateMirror.sol";

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
        loanStateMirror = new LoanStateMirror();
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
}
