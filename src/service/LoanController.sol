// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {LoanControllerErrors} from "../errors/Errors.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IGlobalStateManager} from "../interfaces/IGlobalStateManager.sol";
import {IStateAggregator} from "../interfaces/IStateAggregator.sol";
import {ILendingPoolContract} from "../interfaces/ILendingPoolContract.sol";
import {LoanManager} from "../GSM/LoanManager.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {IVault} from "../interfaces/IVault.sol";
import {LendingPoolContract} from "../LendingPoolContract.sol";
import {ICrossChainMessageSender} from "../ccip/interfaces/ICrossChainMessageSender.sol";
import {ILoanController} from "./interfaces/ILoanController.sol";

contract LoanController is Ownable, ILoanController {
    IGlobalStateManager GSM;
    IRegistry registry;
    IVault vault;
    ILendingPoolContract lendingPoolContract;
    IStateAggregator stateAggregator;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LTV = 75e16;

    constructor(
        address gsm_,
        address stateAggregator_,
        address lendingPoolContract_,
        address registry_,
        address vault_
    ) Ownable(msg.sender) {
        GSM = IGlobalStateManager(gsm_);
        stateAggregator = IStateAggregator(stateAggregator_);
        lendingPoolContract = ILendingPoolContract(lendingPoolContract_);
        registry = IRegistry(registry_);
        vault = IVault(vault_);
    }

    uint256 ethChainId = 11155111;

    uint256 arbChainId = 421614;

    /// @dev this prevent the user from passing zero value to the contract
    ///

    modifier isGreaterThanZero(uint256 amount) {
        if (amount == 0) {
            revert LoanControllerErrors
                .LoanController__AmountShouldBeGreaterThanZero();
        }
        _;
    }

    function borrowLoanController(
        address user,
        address tokenAddress,
        uint256 collateralChainId,
        uint64 tokenId,
        uint256 amount
    ) external payable onlyOwner {
        bool chainIdentifier = block.chainid == ethChainId;

        uint256 depositedCollateral = chainIdentifier
            ? GSM.getUserCollateralDetails(collateralChainId, user, tokenId)
            : stateAggregator.readCollateralDetailsOfUser(
                collateralChainId,
                user,
                tokenId
            );

        // Calculate the amount of collateral available for lending, considering the LTV ratio
        uint256 collateralAvailableForLending = (depositedCollateral * LTV) /
            PRECISION;
        uint256 collateralAvailableForLendingInUsd = lendingPoolContract
            .getUsdValue(tokenId, collateralAvailableForLending);
        if (amount > collateralAvailableForLendingInUsd) {
            revert LoanControllerErrors.LoanController__NotEnoughCollateral();
        }

        uint256 loanId = chainIdentifier
            ? GSM.readNumberOfLoanTakenPerToken(block.chainid, user, tokenId)
            : stateAggregator.readNumberOfLoanTakenPerToken(
                block.chainid,
                user,
                tokenId
            );

        LoanManager.LoanDetails memory loan;
        // Update the loan details: amount borrowed, collateral used, last update, and due date
        loan.amountBorrowedInUSDT += amount;
        loan.principalAmount += amount;
        loan.asset = tokenAddress;
        loan.collateralChainId = collateralChainId;
        loan.collateralUsed = lendingPoolContract.getTokenAmountFromUsd(
            tokenId,
            amount
        );
        loan.lastUpdate = block.timestamp;
        loan.dueDate = block.timestamp + 180 days;
        loan.token = lendingPoolContract.getStableCoinAddress();
        loan.loanChainId = block.chainid;
        loan.userBorrowIndex = chainIdentifier
            ? GSM.getBorrowerIndex(tokenId)
            : stateAggregator.getBorrowerIndex(tokenId);
        loan.loanId = ++loanId;

        if (chainIdentifier) {
            GSM.updateBorrowLoanDetailsOfUser(
                block.chainid,
                user,
                tokenId,
                loan
            );
            uint64 arbDestinationChainSelector = registry
                .getDestinationChainSelector(arbChainId);
            address arbCrossChainReceiverAddress = registry
                .getCrossChainAddress(
                    arbDestinationChainSelector,
                    "crossChainMessageReceiverAddress"
                );
            GSM.mirrorUpdateOfTheUserLoan(
                arbCrossChainReceiverAddress,
                block.chainid,
                user,
                tokenId,
                loan.loanId,
                arbDestinationChainSelector
            );
        } else {
            uint64 ethDestinationChainSelector = registry
                .getDestinationChainSelector(ethChainId);

            address receiver = registry.getCrossChainAddress(
                ethDestinationChainSelector,
                "crossChainMessageReceiverAddress"
            );
            address crossChainMessageSender = registry.getAddress(
                block.chainid,
                "crossChainMessageSenderAddress"
            );

            bytes memory extraInf = abi.encode(loan);
            bytes memory data = abi.encode(
                lendingPoolContract.getActionCommunicationId(),
                LendingPoolContract.CrossChainPayLoad({
                    actionType: LendingPoolContract.ActionType.LOAN_TAKEN,
                    chainId: block.chainid,
                    user: user,
                    crossChaintokenId: tokenId,
                    amountToTransfer: 0,
                    messageToTransfer: "",
                    extraInformation: extraInf
                })
            );
            uint256 fees = ICrossChainMessageSender(crossChainMessageSender)
                .getFee(
                    receiver,
                    data,
                    ethDestinationChainSelector,
                    address(0),
                    0,
                    false
                );
            if (msg.value < fees) {
                revert LoanControllerErrors.LoanController__InsufficentFees();
            }
            (bool success, ) = payable(address(crossChainMessageSender)).call{
                value: fees
            }("");
            if (!success) {
                revert LoanControllerErrors.LoanController__TransferFailed();
            }
            ICrossChainMessageSender(crossChainMessageSender)
                .sendViaNativeToken(
                    receiver,
                    data,
                    ethDestinationChainSelector,
                    address(0),
                    amount
                );
        }
        vault.transferLoanAmount(user, amount);
        emit LendingPoolContract.LoanBorrowed(user, tokenAddress, loan, amount);
    }

    function repayLoanController(
        address user,
        address tokenAddress,
        uint256 loanChainId,
        uint64 tokenId,
        uint256 amount,
        uint256 loanId
    ) external payable onlyOwner {
        bool chainIdentififer = block.chainid == ethChainId;
        LoanManager.LoanDetails memory loan = chainIdentififer
            ? GSM.readLoanDetailsOfUser(loanChainId, user, tokenId, loanId)
            : stateAggregator.readLoanDetailsOfUser(
                loanChainId,
                user,
                tokenId,
                loanId
            );
        uint256 principalLoanAmount = loan.amountBorrowedInUSDT;
        uint256 userBorrowIndex = loan.userBorrowIndex;
        uint256 scaledLoanAmount = (principalLoanAmount *
            (
                chainIdentififer
                    ? GSM.getBorrowerIndex(tokenId)
                    : stateAggregator.getBorrowerIndex(tokenId)
            )) / userBorrowIndex;
        uint256 interestAccrued = scaledLoanAmount - principalLoanAmount;
        uint256 interestPaidNow = 0;
        uint256 principalRepaid = 0;
        if (amount > scaledLoanAmount) {
            revert LoanControllerErrors.LoanController__LoanAmountExceeded();
        }

        vault.claimLoan(user, amount);
        if (amount <= interestAccrued) {
            // Entire repayment goes to pay interest only
            interestPaidNow = amount;
            // Loan remains with the same principal but less interest
            scaledLoanAmount =
                loan.amountBorrowedInUSDT +
                (interestAccrued - interestPaidNow);
        } else {
            // Repays full interest and some (or all) principal
            interestPaidNow = interestAccrued;
            principalRepaid = amount - interestPaidNow;
            // Update the new loan amount after principal repayment
            scaledLoanAmount = loan.amountBorrowedInUSDT - principalRepaid;
        }

        loan.amountBorrowedInUSDT = scaledLoanAmount;
        loan.interestPaid += interestPaidNow;
        // modify this part to update the collateral of the user in the gsm and arrange it to release the collateral from the chain
        if (loan.amountBorrowedInUSDT != 0) {
            loan.lastUpdate = block.timestamp;
            loan.userBorrowIndex = (
                chainIdentififer
                    ? GSM.getBorrowerIndex(tokenId)
                    : stateAggregator.getBorrowerIndex(tokenId)
            );
        } else {
            loan.isClosed = true;
        }
        if (chainIdentififer) {
            GSM.repayLoanDetailsOfUser(loanChainId, user, tokenId, loan);
            uint64 destinationChainSelector = registry
                .getDestinationChainSelector(421614);

            address receiver = registry.getCrossChainAddress(
                destinationChainSelector,
                "crossChainMessageReceiverAddress"
            );

            GSM.mirrorUpdateOfTheUserLoan(
                receiver,
                loanChainId,
                user,
                tokenId,
                loan.loanId,
                destinationChainSelector
            );
        } else {
            uint64 ethDestinationChainSelector = registry
                .getDestinationChainSelector(ethChainId);

            address receiver = registry.getCrossChainAddress(
                ethDestinationChainSelector,
                "crossChainMessageReceiverAddress"
            );
            bytes memory extraInf = abi.encode(loan);
            bytes memory data = abi.encode(
                lendingPoolContract.getActionCommunicationId(),
                LendingPoolContract.CrossChainPayLoad({
                    actionType: LendingPoolContract.ActionType.LOAN_REPAYMENT,
                    chainId: block.chainid,
                    user: user,
                    crossChaintokenId: tokenId,
                    amountToTransfer: 0,
                    messageToTransfer: "",
                    extraInformation: extraInf
                })
            );
            address crossChainMessageSender = registry.getAddress(
                block.chainid,
                "crossChainMessageSenderAddress"
            );
            uint256 fees;
            try
                ICrossChainMessageSender(crossChainMessageSender).getFee(
                    receiver,
                    data,
                    ethDestinationChainSelector,
                    address(0),
                    0,
                    false
                )
            returns (uint256 fees_) {
                fees = fees_;
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("getFee failed: ", reason)));
            } catch {
                revert("getFee failed: unknown reason");
            }

            if (msg.value < fees) {
                revert LoanControllerErrors.LoanController__InsufficentFees();
            }
            (bool success, ) = payable(address(crossChainMessageSender)).call{
                value: fees
            }("");
            if (!success) {
                revert LoanControllerErrors.LoanController__TransferFailed();
            }
            ICrossChainMessageSender(crossChainMessageSender)
                .sendViaNativeToken(
                    receiver,
                    data,
                    ethDestinationChainSelector,
                    address(0),
                    amount
                );
        }
        emit LendingPoolContract.LoanRepaid(
            user,
            tokenAddress,
            amount,
            interestPaidNow,
            principalRepaid
        );
    }
}
