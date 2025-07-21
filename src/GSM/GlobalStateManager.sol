// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GlobalStateManagerErrors} from "../errors/Errors.sol";
import {IGlobalStateManager} from "../interfaces/IGlobalStateManager.sol";
import {ILendingPoolContract} from "../interfaces/ILendingPoolContract.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CollateralManager} from "./CollateralManager.sol";
import {LoanManager} from "./LoanManager.sol";
import {LiquidityManager} from "./LiquidityManager.sol";
import {LPTokenManager} from "./LPTokenManager.sol";
import {InterestRateManager} from "./InterestRateManager.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {ICrossChainMessageSender} from "../ccip/interfaces/ICrossChainMessageSender.sol";
import {LendingPoolContract} from "../LendingPoolContract.sol";
import {console} from "forge-std/console.sol";
import {GlobalStateManagerErrors} from "../errors/Errors.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

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

    LiquidityManager liquidityManager;

    LPTokenManager lpTokenManager;

    InterestRateManager interestRateManager;

    ILendingPoolContract lendingPoolContract;

    uint256 private constant LIQUIDATION_PENALTY = 5e16; // 5% penalty on LIQUIDATION_PENALTY

    /// @dev The precision factor used for calculations involving token amounts or decimals
    /// @notice This constant defines the precision (1e18) for scaling values to match token precision or to avoid precision loss

    uint256 private constant PRECISION = 1e18;

    /// @notice Emitted when a user's loan is liquidated due to insufficient collateral.
    /// @param user The address of the user whose loan was liquidated.
    /// @param token The address of the token associated with the loan.
    /// @param loanAmount The total outstanding loan amount at the time of liquidation.
    /// @param collateralValue The USD value of the user's collateral.
    /// @param liquidationPenalty The penalty amount applied during liquidation.

    event LoanLiquidated(
        address indexed user,
        address indexed token,
        uint256 loanAmount,
        uint256 collateralValue,
        uint256 liquidationPenalty
    );

    constructor(
        address registry_,
        address interestRateModel
    ) Ownable(msg.sender) {
        collateralManager = new CollateralManager();
        loanManager = new LoanManager();
        liquidityManager = new LiquidityManager();
        lpTokenManager = new LPTokenManager();
        registry = IRegistry(registry_);
        interestRateManager = new InterestRateManager(interestRateModel);
        interestRateManager.setInitalBorrowerIndex(0);
    }

    function setLendingPoolContractAddress(
        address lendingPoolContract_
    ) external onlyOwner {
        lendingPoolContract = ILendingPoolContract(lendingPoolContract_);
    }

    function setCrosssChainMessageSenderAddress(
        address crossChainMessageSender_
    ) external onlyOwner {
        crossChainMessageSender = ICrossChainMessageSender(
            crossChainMessageSender_
        );
    }

    function setParamsCrossChain(
        address receiver,
        uint256 chainId_,
        uint64 destinationChainSelector
    ) external {
        bytes memory data = abi.encode(
            uint64(1), // Identifier for response payload
            LendingPoolContract.CrossChainResponsePayLoad({
                response: LendingPoolContract
                    .Response
                    .RESPONSE_SET_INITAL_PARAMS,
                user: address(0),
                chainId: chainId_,
                crossChainTokenId: 0,
                amount: 0,
                timeOfResponse: block.timestamp,
                messageToTransfer: "",
                extraInformation: abi.encode(
                    uint64(0),
                    interestRateManager.getBorrowerIndex(0)
                )
            })
        );

        // Send the payload to the receiver contract on the destination chain using native token mode.
        // @test: first test resposen to the send message(1)
        crossChainMessageSender.sendViaNativeToken(
            receiver,
            data,
            destinationChainSelector,
            address(0), // No token attached in this message
            0
        );
    }

    // only the lending pool contract of the main chain and the cross chain senders
    // of the other chains can call this state manager contract
    // this need to be implemented

    modifier isChainRegesitedToCall() {
        if (!s_isAllowedToCall[msg.sender]) {
            revert GlobalStateManagerErrors.GlobalStateManager__InvalidSender(
                msg.sender
            );
        }
        _;
    }

    function setAllowedChains(address sender) external onlyOwner {
        if (sender != address(0)) {
            s_isAllowedToCall[sender] = true;
        }
    }

    function getTotalCollateralPerToken(
        uint64 tokenId
    ) external view returns (uint256) {
        return collateralManager.getTotalCollateralPerToken(tokenId);
    }

    function getTotalLiquidityPerToken(
        uint64 tokenId
    ) external view returns (uint256) {
        return liquidityManager.getTotalLiquidityPerToken(tokenId);
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
    ) public isChainRegesitedToCall {
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

    function updateBorrowLoanDetailsOfUser(
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
        interestRateManager.updateInterestRate(tokenId);
    }

    function repayLoanDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        LoanManager.LoanDetails memory loanDetails
    ) external isChainRegesitedToCall {
        interestRateManager.updateInterestRate(tokenId);
        loanManager.updateLoanDetailsOfUser(
            chainId,
            user,
            tokenId,
            loanDetails.loanId,
            loanDetails
        );

        if (loanDetails.isClosed == true) {
            collateralManager.unlockCollateralOfUser(
                loanDetails.collateralChainId,
                user,
                tokenId,
                loanDetails.collateralUsed
            );
        }
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
    ) public isChainRegesitedToCall {
        LoanManager.LoanDetails memory loan = loanManager.getLoanDetailsOfUser(
            chainId_,
            user_,
            tokenId,
            loanId
        );

        console.log(loan.amountBorrowedInUSDT);

        console.log("index:", interestRateManager.getBorrowerIndex(tokenId));
        bytes memory extraInfo = abi.encode(
            loanManager.getLoanDetailsOfUser(chainId_, user_, tokenId, loanId),
            interestRateManager.getBorrowerIndex(tokenId)
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

    // DEPOSIT DETAILS

    function updateDepositDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external {
        liquidityManager.updateDepositDetailsOfUser(
            chainId,
            user,
            tokenId,
            amount
        );
        interestRateManager.updateInterestRate(tokenId);
    }

    function updateWithDrawDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external {
        liquidityManager.updateWithDrawDetailsOfUser(
            chainId,
            user,
            tokenId,
            amount
        );
        interestRateManager.updateInterestRate(tokenId);
    }

    function readDepositDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256) {
        return liquidityManager.getDepositDetailsOfUser(chainId, user, tokenId);
    }

    function readTotalLiquidityPerChainPerToken(
        uint256 chainId,
        uint64 tokenId
    ) external view returns (uint256) {
        return
            liquidityManager.getTotalLiquidityPerChainPerToken(
                chainId,
                tokenId
            );
    }

    function readTotalLiquidityPerToken(
        uint64 tokenId
    ) external view returns (uint256) {
        return liquidityManager.getTotalLiquidityPerToken(tokenId);
    }

    function mirrorUpdateOfTheUserDeposit(
        address receiver,
        uint256 chainId_,
        address user_,
        uint64 tokenId,
        uint64 destinationChainSelector
    ) external isChainRegesitedToCall {
        uint256 amountDeposited = liquidityManager.getDepositDetailsOfUser(
            chainId_,
            user_,
            tokenId
        );
        bytes memory extraInfo = mirrorUpdateLPTokens(chainId_, user_, tokenId);

        bytes memory data = abi.encode(
            uint64(1),
            LendingPoolContract.CrossChainResponsePayLoad({
                response: LendingPoolContract
                    .Response
                    .RESPONSE_DEPOSIT_INFORMATION_FOR_USER,
                user: user_,
                chainId: chainId_,
                crossChainTokenId: tokenId,
                amount: amountDeposited,
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

    // LP TOKEN MANAGER

    function updateLPTokenInCirculation(
        uint256 chainId,
        address user,
        uint256 amount
    ) external {
        lpTokenManager.updateLpTokenInCirculation(chainId, user, amount);
    }

    function getLpTokensPerUser(address user) external view returns (uint256) {
        return lpTokenManager.getLpTokensPerUser(user);
    }

    function getLpTokensPerUserPerChain(
        uint256 chainId,
        address user
    ) external view returns (uint256) {
        return lpTokenManager.getLpTokensPerUserPerChain(chainId, user);
    }

    function getTotalLpTokensInAChain(
        uint256 chainId
    ) external view returns (uint256) {
        return lpTokenManager.getTotalLpTokensInAChain(chainId);
    }

    function getTotalLpTokensInCirculation() external view returns (uint256) {
        return lpTokenManager.getTotalLpTokensInCirculation();
    }

    function totalLPTokensInCirculation() external view returns (uint256) {
        return lpTokenManager.getTotalLpTokensInCirculation();
    }

    function mirrorUpdateLPTokens(
        uint256 chainId_,
        address user_,
        uint64 tokenId
    ) private view returns (bytes memory) {
        return
            abi.encode(
                lpTokenManager.getLpTokensPerUser(user_),
                lpTokenManager.getLpTokensPerUserPerChain(chainId_, user_),
                lpTokenManager.getTotalLpTokensInAChain(chainId_),
                lpTokenManager.getTotalLpTokensInCirculation(),
                interestRateManager.getBorrowerIndex(tokenId)
            );
    }

    // BORROWER INDEX

    function getBorrowerIndex(uint64 tokenId) external view returns (uint256) {
        return interestRateManager.getBorrowerIndex(tokenId);
    }

    // liquidate function
    /**
     * @notice This function allows the liquidation of a borrower's loan if the value of their collateral falls below the required threshold.
     *
     * @dev
     * - A loan is considered liquidatable if the value of the collateral is lower than the required liquidation value.
     * - In such cases, the collateral is transferred from the borrower’s account to the liquidity pool, and the loan is removed from the system.
     * - This function also ensures that only approved tokens can be used for liquidation and that it cannot be re-entered during execution (non-reentrancy check).
     *
     * The liquidation process involves:
     * 1. Verifying that the loan is still active by checking if the borrower owes an outstanding amount.
     * 2. Determining the current value of the collateral in USD using the token’s price feed.
     * 3. Comparing the value of the collateral against the liquidation threshold, which is calculated as the loan amount plus a liquidation penalty.
     * 4. If the collateral value is below the liquidation threshold, the collateral is moved back to the liquidity pool and the loan is cleared from the system.
     * 5. If the collateral is above the liquidation threshold, the liquidation is rejected, and the loan remains active.
     *
     * @param user The address of the borrower whose loan is being liquidated.
     * @param tokenId The address of the token used for the loan (the token collateralized by the borrower).
     *
     *
     *
     * @dev
     * This function will emit the `LoanLiquidated` event when the liquidation is successful.
     * The event contains details about the loan that was liquidated, including the amount borrowed, the value of collateral, and the liquidation threshold.
     *
     * @dev
     * Requirements:
     * - The `token` must be approved by the contract for liquidation.
     * - The loan must exist and be active.
     * - The collateral value must fall below the required liquidation value for the liquidation to proceed.
     *
     * @custom:revert LendingPoolContract__LoanIsNotActive The loan does not exist or has been fully repaid, so it cannot be liquidated.
     * @custom:revert LendingPoolContract__NotLiquidatable The collateral value is greater than the liquidation threshold, so liquidation is not possible.
     *
     * event LoanLiquidated
     * - Emitted when a loan is successfully liquidated.
     * - Contains details of the loan amount, collateral value, and liquidation value.
     */

    function liquidate(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId
    ) internal {
        address tokenAddress = lendingPoolContract.getTokenAddressFromTokenId(
            tokenId
        );
        LoanManager.LoanDetails memory loan = loanManager.getLoanDetailsOfUser(
            chainId,
            user,
            tokenId,
            loanId
        );
        uint256 loanAmount = loan.amountBorrowedInUSDT;
        if (loanAmount == 0) {
            revert GlobalStateManagerErrors
                .GlobalStateManager__LoanIsNotActive();
        }
        uint256 collateralValueInUSD = lendingPoolContract.getUsdValue(
            tokenId,
            loan.collateralUsed
        );
        uint256 liquidationValue = (loanAmount * LIQUIDATION_PENALTY) /
            PRECISION;
        if (collateralValueInUSD > liquidationValue && loan.penaltyCount < 2) {
            revert GlobalStateManagerErrors
                .GlobalStateManager__NotLiquidatable();
        }
        liquidityManager.addLiquidity(
            loan.collateralChainId,
            tokenId,
            loan.collateralUsed
        );
        if (loanAmount > loanManager.readTotalBorrwedPerToken(tokenId)) {
            loanManager.updateAddBorrowedPerToken(tokenId, 0);
        } else {
            loanManager.updateRemoveBorrowedPerToken(
                tokenId,
                loan.collateralUsed
            );
            liquidityManager.addLiquidity(
                chainId,
                tokenId,
                loan.collateralUsed
            );
        }
        loanManager.deleteLoanDetails(chainId, user, tokenId, loan.loanId);
        uint64 destinationChainSelector = registry.getDestinationChainSelector(
            421614
        );

        address receiver = registry.getCrossChainAddress(
            destinationChainSelector,
            "crossChainMessageReceiverAddress"
        );

        mirrorUpdateOfTheUserLoan(
            receiver,
            chainId,
            user,
            tokenId,
            loanId,
            destinationChainSelector
        );
        emit LoanLiquidated(
            user,
            tokenAddress,
            loanAmount,
            collateralValueInUSD,
            liquidationValue
        );
    }

    /**
     * @notice Checks if any borrower's loan has passed its due date and requires liquidation.
     * @dev This function is used by Chainlink Keepers (or any automated service) to determine if maintenance work is needed.
     * It loops through all borrowers and their loan tokens to find any overdue loans.
     * If an overdue loan is found, it returns `true` with encoded borrower and token information.
     * If no overdue loans are found, it returns `false` and empty performData.
     *
     * checkData Not used in this function. Included to match the KeeperCompatibleInterface.
     * @return upkeepNeeded A boolean value indicating whether upkeep (liquidation) is needed.
     * @return performData Encoded data containing the borrower address and token address to be used in performUpkeep.
     */

    function checkUpkeep(
        bytes calldata /* checkData */
    ) external view returns (bool upkeepNeeded, bytes memory performData) {
        for (uint256 i = 0; i < loanManager.getLengthOfBorrowerArray(); i++) {
            address borrower = loanManager.getBorrower(i);
            uint256[] memory chains = loanManager.getLoanChainsForTheUser(
                borrower
            );
            uint64[] memory tokens = loanManager.getLoanTokensForTheUser(
                borrower
            );

            for (uint256 c = 0; c < chains.length; c++) {
                for (uint256 t = 0; t < tokens.length; t++) {
                    uint256 loanCount = loanManager
                        .getNumberOfLoansTakenPerToken(
                            chains[c],
                            borrower,
                            tokens[t]
                        );

                    for (uint256 l = 0; l < loanCount; l++) {
                        LoanManager.LoanDetails memory loan = loanManager
                            .getLoanDetailsOfUser(
                                chains[c],
                                borrower,
                                tokens[t],
                                l
                            );

                        uint256 collateralValueInUSD = lendingPoolContract
                            .getUsdValue(tokens[t], loan.collateralUsed);

                        uint256 liquidationValue = (loan.amountBorrowedInUSDT *
                            LIQUIDATION_PENALTY) / PRECISION;

                        if (
                            block.timestamp > loan.dueDate ||
                            collateralValueInUSD < liquidationValue
                        ) {
                            return (
                                true,
                                abi.encode(borrower, chains[c], tokens[t], l)
                            );
                        }
                    }
                }
            }
        }
        return (false, "");
    }

    /**
     * @notice Performs the upkeep by liquidating overdue loans.
     * @dev This function is triggered by Chainlink Keepers (or other automated services)
     * when `checkUpkeep` signals that upkeep is needed. It decodes the borrower and token from
     * the `performData`, checks if the loan is overdue, and if so, calls the `liquidate` function.
     *
     * @param performData Encoded data containing the borrower's address and the token address,
     * produced by `checkUpkeep`.
     */
    function performUpkeep(bytes calldata performData) external {
        (
            uint256 chainId,
            address borrower,
            uint64 tokenId,
            uint256 loanId
        ) = abi.decode(performData, (uint256, address, uint64, uint256));
        LoanManager.LoanDetails memory loan = loanManager.getLoanDetailsOfUser(
            chainId,
            borrower,
            tokenId,
            loanId
        );
        if (block.timestamp < loan.dueDate) {
            return;
        }
        if (loan.penaltyCount < 2) {
            loan.penaltyCount++;
            loan.dueDate = block.timestamp + 30 days;
            loan.amountBorrowedInUSDT +=
                (loan.amountBorrowedInUSDT * LIQUIDATION_PENALTY) /
                PRECISION;
        } else {
            liquidate(chainId, borrower, tokenId, loanId);
        }
    }
}
