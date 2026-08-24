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
    mapping(address caller => bool) private s_isAllowedToCall;

    CollateralManager collateralManager;

    LoanManager loanManager;

    IRegistry registry;

    ICrossChainMessageSender crossChainMessageSender;

    LiquidityManager liquidityManager;

    LPTokenManager lpTokenManager;

    InterestRateManager interestRateManager;

    ILendingPoolContract lendingPoolContract;

    uint256 private constant LIQUIDATION_PENALTY = 5e16;


    uint256 private constant PRECISION = 1e18;

    // Mirrored to the satellite on liquidation. Settable so a local deployment
    // can run on non-colliding chain ids; defaults match the live testnets.
    uint256 public ethChainId = 11155111;
    uint256 public arbChainId = 421614;

    function setChainIds(uint256 ethChainId_, uint256 arbChainId_) external onlyOwner {
        ethChainId = ethChainId_;
        arbChainId = arbChainId_;
    }


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
            uint64(1),
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

        crossChainMessageSender.sendViaNativeToken(
            receiver,
            data,
            destinationChainSelector,
            address(0),
            0
        );
    }


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

    function getTotalBorrowedPerToken(
        uint64 tokenId
    ) external view returns (uint256) {
        return loanManager.readTotalBorrwedPerToken(tokenId);
    }


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


    function mirrorUpdateOfTheUserCollateral(
        address receiver,
        uint256 chainId_,
        address user_,
        uint64 tokenId,
        uint64 destinationChainSelector
    ) public isChainRegesitedToCall {
        uint256 userCollateralDetails = getUserCollateralDetails(
            chainId_,
            user_,
            tokenId
        );
        bytes memory data = abi.encode(
            uint64(1),
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

        crossChainMessageSender.sendViaNativeToken(
            receiver,
            data,
            destinationChainSelector,
            address(0),
            0
        );
    }


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


    function getBorrowerIndex(uint64 tokenId) external view returns (uint256) {
        return interestRateManager.getBorrowerIndex(tokenId);
    }

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
            arbChainId
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
    function checkUpkeep(
        bytes calldata
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
                    // Loan ids are 1-based (LoanController assigns
                    // `loan.loanId = ++loanId`), so scanning from 0 read an
                    // empty slot for every borrower and missed the real loans.
                    for (uint256 l = 1; l <= loanCount; l++) {
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
                            // Field order must match performUpkeep's decode —
                            // (chainId, borrower, tokenId, loanId). Emitting
                            // borrower first made every keeper run decode the
                            // address as a chain id and act on nothing.
                            return (
                                true,
                                abi.encode(chains[c], borrower, tokens[t], l)
                            );
                        }
                    }
                }
            }
        }
        return (false, "");
    }
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
            // `loan` is a memory copy, so the escalation above is discarded
            // unless it is written back. Without this the penalty count never
            // advances, never reaches 2, and `liquidate` below is unreachable.
            loanManager.updateLoanDetailsOfUser(
                chainId,
                borrower,
                tokenId,
                loanId,
                loan
            );
        } else {
            liquidate(chainId, borrower, tokenId, loanId);
        }
    }
}
