// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GlobalStateManagerErrors} from "../errors/Errors.sol";
import {IGlobalStateManager} from "../interfaces/IGlobalStateManager.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CollateralManager} from "./CollateralManager.sol";
import {LoanManager} from "./LoanManager.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {ICrossChainMessageSender} from "../ccip/interfaces/ICrossChainMessageSender.sol";
import {LendingPoolContract} from "../LendingPoolContract.sol";
import {console} from "forge-std/console.sol";

contract GlobalStateManager is IGlobalStateManager, Ownable {
    /// @dev Tracks whether a specific address is allowed to call restricted functions.
    mapping(address caller => bool) private s_isAllowedToCall;

    /// @notice Contract responsible for managing user collateral across chains.
    CollateralManager collateralManager;

    /// @notice Contract responsible for managing loan creation, repayment, and state.
    LoanManager loanManager;

    /// @notice Registry contract used for fetching global system configuration and references.
    IRegistry registry;

    /// @notice Interface for sending cross-chain messages to other blockchain networks.
    ICrossChainMessageSender crossChainMessageSender;

    constructor(address registry_) Ownable(msg.sender) {
        collateralManager = new CollateralManager();
        loanManager = new LoanManager();
        registry = IRegistry(registry_);
    }

    function setCrosssChainMessageSenderAddress(
        address crossChainMessageSender_
    ) external onlyOwner {
        crossChainMessageSender = ICrossChainMessageSender(
            crossChainMessageSender_
        );
    }

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

    // COLLATERAL SECTION

    function updateDepositCollateralOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external isChainRegesitedToCall {
        collateralManager.updateDepositCollateralDetailsOfUser(
            chainId,
            user,
            tokenId,
            amount
        );
    }

    function updateWithdrawCollateralOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external isChainRegesitedToCall {
        collateralManager.updateWithdrawCollateralDetailsOfUser(
            chainId,
            user,
            tokenId,
            amount
        );
    }

    function getUserCollateralDetails(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) public view returns (uint256) {
        return
            collateralManager.getUserCollateralDetails(chainId, user, tokenId);
    }

    function getTotalCollateralDetails(
        uint256 chainId,
        uint64 tokenId
    ) external view returns (uint256) {
        return
            collateralManager.getTotalCollateralDepositedPerChainPerToken(
                chainId,
                tokenId
            );
    }

    /// @notice Sends a mirrored update of a user’s collateral information to a contract on another chain.
    /// @dev This function is used to synchronize collateral data across chains via a cross-chain message using native tokens.
    /// @param receiver The address on the destination chain that will receive and process the collateral update.
    /// @param chainId_ The ID of the chain where the original collateral data is stored.
    /// @param user_ The address of the user whose collateral data is being mirrored.
    /// @param tokenId The ID of the collateral token whose data is being transferred.
    /// @param destinationChainSelector The selector (Chainlink CCIP identifier) for the destination chain.

    function mirrorUpdateOfTheUserCollateral(
        address receiver,
        uint256 chainId_,
        address user_,
        uint64 tokenId,
        uint64 destinationChainSelector
    ) external isChainRegesitedToCall {
        // Fetch the user's collateral amount for the given chain and token.
        uint256 userCollateralDetails = getUserCollateralDetails(
            chainId_,
            user_,
            tokenId
        );
        // Prepare the encoded message payload for cross-chain delivery.
        bytes memory data = abi.encode(
            uint64(1), // Identifier for response payload
            LendingPoolContract.CrossChainResponsePayLoad({
                response: LendingPoolContract
                    .Response
                    .RESPONSE_COLLATERAL_INFORMATION_FOR_USER,
                user: user_,
                chainId: chainId_,
                crossChainTokenId: tokenId,
                amount: userCollateralDetails,
                timeOfResponse: block.timestamp,
                messageToTransfer: "",
                extraInformation: ""
            })
        );

        // Send the payload to the receiver contract on the destination chain using native token mode.
        crossChainMessageSender.sendViaNativeToken(
            receiver,
            data,
            destinationChainSelector,
            address(0), // No token attached in this message
            0
        );
    }

    // LOAN DETAILS

    function updateLoanDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        LoanManager.LoanDetails memory loanDetails
    ) external isChainRegesitedToCall {
        loanManager.updateLoanDetailsOfUser(
            chainId,
            user,
            tokenId,
            loanDetails.loanId,
            loanDetails
        );
        collateralManager.lockCollateralOfUser(
            loanDetails.collateralChainId,
            user,
            tokenId,
            loanDetails.collateralUsed
        );
        loanManager.updateNumberOfLoansTaken(
            chainId,
            user,
            tokenId,
            loanDetails.loanId
        );
    }

    function readLoanDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId
    ) external view returns (LoanManager.LoanDetails memory) {
        return loanManager.getLoanDetailsOfUser(chainId, user, tokenId, loanId);
    }

    function readNumberOfLoanTakenPerToken(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256) {
        return
            loanManager.getNumberOfLoansTakenPerToken(chainId, user, tokenId);
    }

    function mirrorUpdateOfTheUserLoan(
        address receiver,
        uint256 chainId_,
        address user_,
        uint64 tokenId,
        uint256 loanId,
        uint64 destinationChainSelector
    ) external isChainRegesitedToCall {
        bytes memory extraInfo = abi.encode(
            loanManager.getLoanDetailsOfUser(chainId_, user_, tokenId, loanId)
        );
        bytes memory data = abi.encode(
            uint64(1),
            LendingPoolContract.CrossChainResponsePayLoad({
                response: LendingPoolContract
                    .Response
                    .RESPONSE_LOAN_INFORMATION_FOR_USER,
                user: user_,
                chainId: chainId_,
                crossChainTokenId: tokenId,
                amount: 0,
                timeOfResponse: block.timestamp,
                messageToTransfer: "",
                extraInformation: extraInfo
            })
        );
        crossChainMessageSender.sendViaNativeToken(
            receiver,
            data,
            destinationChainSelector,
            address(0),
            0
        );
    }
}
