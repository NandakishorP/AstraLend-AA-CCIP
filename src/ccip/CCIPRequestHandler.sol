// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {LendingPoolContract} from "../LendingPoolContract.sol";
pragma solidity ^0.8.20;
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {LendingPoolContract} from "../LendingPoolContract.sol";
import {IGlobalStateManager} from "../interfaces/IGlobalStateManager.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {ILendingPoolContract} from "../interfaces/ILendingPoolContract.sol";
import {ICrossChainMessageSender} from "./interfaces/ICrossChainMessageSender.sol";
import {ICCIPRequestHandler} from "./interfaces/ICCIPRequestHandler.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";
import {LoanManager} from "../GSM/LoanManager.sol";

contract CCIPRequestHandler is ICCIPRequestHandler, Ownable {
    /// @notice Interface to manage and update global state (like loan or collateral states) across chains.
    IGlobalStateManager GSM;

    /// @notice Interface to access the registry for retrieving cross-chain contract addresses by name and chain ID.
    IRegistry registry;

    /// @notice Chain ID representing Ethereum Sepolia testnet. Used to determine if execution context is on Sepolia.
    uint256 ethChainId = 11155111; // for sepolia now

    /// @notice Interface to send messages to other chains via a cross-chain messaging protocol (e.g., CCIP).
    ICrossChainMessageSender crossChainMessageSender;

    /// @notice Interface to the LendingPoolContract for interacting with lending and borrowing functionalities.
    ILendingPoolContract lendingPoolContract;

    error OnlyOwnerCanCall();
    error InvalidChain__OnlyEthSupported();

    constructor(
        address lendingPoolContract_,
        address registry_,
        address gsm_,
        address crossChainMessageSender_
    ) Ownable(msg.sender) {
        GSM = IGlobalStateManager(gsm_);
        registry = IRegistry(registry_);

        crossChainMessageSender = ICrossChainMessageSender(
            crossChainMessageSender_
        );

        lendingPoolContract = ILendingPoolContract(lendingPoolContract_);
    }

    function setGSMAddress(address gsm) external onlyOwner {
        if (block.chainid != ethChainId) {
            revert InvalidChain__OnlyEthSupported();
        }
        GSM = IGlobalStateManager(gsm);
    }

    function updateDepositCollateralDetailsOfUser(
        LendingPoolContract.CrossChainPayLoad memory actionPayLoad
    ) external {
        GSM.updateDepositCollateralOfUser(
            actionPayLoad.chainId,
            actionPayLoad.user,
            actionPayLoad.crossChaintokenId,
            actionPayLoad.amountToTransfer
        );
    }

    function updateWithdrawDepositCollateralDetailsOfUser(
        LendingPoolContract.CrossChainPayLoad memory actionPayLoad
    ) external {
        GSM.updateWithdrawCollateralOfUser(
            actionPayLoad.chainId,
            actionPayLoad.user,
            actionPayLoad.crossChaintokenId,
            actionPayLoad.amountToTransfer
        );
    }

    function updateCollateralStateMirror(
        address receiver,
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint64 destinationChainSelector
    ) external {
        GSM.mirrorUpdateOfTheUserCollateral(
            receiver,
            chainId,
            user,
            tokenId,
            destinationChainSelector
        );
    }

    function updateLoanDetailsOfUser(
        LendingPoolContract.CrossChainPayLoad memory actionPayLoad
    ) external {
        GSM.updateLoanDetailsOfUser(
            actionPayLoad.chainId,
            actionPayLoad.user,
            actionPayLoad.crossChaintokenId,
            abi.decode(
                actionPayLoad.extraInformation,
                (LoanManager.LoanDetails)
            )
        );
    }

    function updateLoanStateMirror(
        address receiver,
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId,
        uint64 destinationChainSelector
    ) external {
        GSM.mirrorUpdateOfTheUserLoan(
            receiver,
            chainId,
            user,
            tokenId,
            loanId,
            destinationChainSelector
        );
    }
}
