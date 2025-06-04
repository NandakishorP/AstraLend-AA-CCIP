// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LpToken} from "../src/tokens/LpTokenContract.sol";
import {StableCoin} from "../src/tokens/StableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILpToken} from "./interfaces/ILpToken.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AggregatorV3Interface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {IInterestRateModel} from "../src/interfaces/IInterestRateModel.sol";
import {ILendingPoolContract} from "../src/interfaces/ILendingPoolContract.sol";
import {LendingPoolContractErrors} from "./errors/Errors.sol";
import {console} from "forge-std/console.sol";
import {Vault} from "./Vault.sol";
import {IVault} from "./interfaces/IVault.sol";
import {CrossChainMessageSender} from "./ccip/CrossChainMessageSender.sol";
import {CrossChainMessageReceiver} from "./ccip/CrossChainMessageReceiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IGlobalStateManager} from "./interfaces/IGlobalStateManager.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";

import {CCIPRequestHandler} from "../src/ccip/CCIPRequestHandler.sol";
import {CCIPResponseHandler} from "../src/ccip/CCIPResponseHandler.sol";

// Layout of Contract:
// version
// imports
// interfaces, libraries, 6contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions
// core functions to implement
/*
    depoist function:
                      the users will be able to deposit collateral into this contract and then get the money back in the form of the stable coins
                      it will accept only specified blue chip cryptocurreinces as collateral. They are defined as per the deployer and its his freedom
    borrow function:

    repay funciton:

    withdraw function:

    gethealthfactor
*/
contract LendingPoolContract is
    ReentrancyGuard,
    AutomationCompatibleInterface,
    ILendingPoolContract,
    Ownable
{
    ////////////////////
    // Using directives
    ////////////////////
    using SafeERC20 for IERC20;

    ////////////////////
    // State Variable
    ////////////////////
    //private variables

    /// @dev Struct representing an active loan taken by a user

    struct LoanDetails {
        address token; // ───────────────────────────────╮ ERC20 token address borrowed by the user
        uint256 amountBorrowedInUSDT; //                 │ Amount borrowed, denominated in USDT (smallest unit: 6 decimals)
        uint256 principalAmount; //                      | The principal amount taken for further reference
        uint256 collateralUsed; //                       │ Collateral amount locked by the user (in collateral token units)
        uint256 lastUpdate; //                           │ Timestamp of the last update to the loan state
        address asset; //                                | Address of the token in which user take the loan
        uint256 userBorrowIndex; //                      | The borrowerIndex of the contract when the user made any last update on the loan
        uint256 interestPaid; //                         | The total interest paid by the user over time
        uint256 liquidationPoint; //                     | The liquidation point for the loan, calculated as LTV * collateral amount
        uint256 dueDate; // ─────────────────────────────╯ Timestamp when the loan repayment is due
        uint8 penaltyCount; // ───────────────────────────────╮ Penalty count  after due date (limit is 2)
        bool isLiquidated; // ────────────────────────────────╯ True if the loan has been liquidated due to default
    }

    /// @notice Tracks the index representing the total interest factor for each token across all borrowers.
    /// @dev This index is used to calculate the compounded interest for each borrower of a specific token.
    /// Each time interest is accrued, this index is updated to reflect the cumulative interest growth.
    /// The individual borrower's interest can be calculated using the difference between the current index
    /// and the index at the time of borrowing.

    mapping(uint64 tokenId => uint256 borrowerIndexOfToken)
        public s_borrowerIndex;

    /// @notice Records the last timestamp when interest was accrued for each token.
    /// @dev This is used to determine how much time has passed since the last interest update for a specific token,
    /// which is essential for calculating how much new interest should be added to the borrower's debt.
    /// Interest accrual operations refer to this timestamp to keep interest calculations accurate and consistent.

    mapping(uint64 tokenId => uint256) public s_lastAccuralTime;

    /// @dev mapping the token addresses to the pricefeed addresses

    mapping(uint64 collateralTokenId => address priceFeedAddress)
        private s_priceFeed;

    /// @dev Mapping to track deposited token amounts per user
    /// @custom:structure mapping(user => mapping(token => amount))

    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => uint256 amount))) s_depositDetailsOfUser;

    /// @dev Tracks loan details for each user per token
    /// @custom:structure mapping(user => mapping(tokenAddress => LoanDetails))

    mapping(address user => mapping(uint64 tokenId => LoanDetails loanDetails))
        private s_loanDetails;

    /// @dev Stores the LP token balance of each user
    /// @custom:structure mapping(user => lpTokenAmount)

    mapping(address user => uint256 lpTokenAmount) private s_tokenDetailsofUser;

    /// @dev address of the lptoken contract

    address private lpToken;

    /// @dev the total liquidity locked in the protocol at the moment for a particular token

    mapping(uint64 tokenId => uint256 totaliquidityOfToken) private s_liquidity;

    /// @dev Tracks the total collateral deposited for each token
    /// @custom:structure mapping(token => totalCollateralAmount)

    mapping(uint64 tokenId => uint256 totalCollateralOfToken)
        private s_tokenCollateral;

    /// @dev Stores the collateral amount for each user per token
    /// @custom:structure mapping(user => mapping(token => collateralAmount))

    mapping(address user => mapping(uint64 tokenId => uint256 amount))
        private s_collateralDetails;

    /// @dev Stores the locked collateral amount for each user per token
    /// @custom:structure mapping(user => mapping(token => lockedCollateralAmount))

    mapping(address user => mapping(uint64 tokenId => uint256 amount))
        private s_lockedCollateralDetails;

    /// @dev checking whether the user has any active loans

    mapping(address user => mapping(uint64 tokenId => bool))
        private s_isBorrower;

    /// @notice Tracks the total amount borrowed for each token across all users.
    /// @dev Maps a token address to the cumulative borrowed amount in that token.

    mapping(uint64 tokenId => uint256 amountBorrowed)
        private s_amountBorrowedInToken;
    /// @notice Stores the list of tokens for which a user has active loans.
    /// @dev Maps a user address to an array of token addresses they have borrowed against.

    mapping(address user => uint64[] tokens) private s_loanTokensForTheUser;

    // mapping the tokenId to the tokenAddress

    mapping(uint64 tokenId => address tokenAddress) private s_tokenAddresses;
    mapping(address tokenAddress => uint64 tokenId) private s_tokenId;

    mapping(bytes32 requestId => uint256 amount)
        private pendingCollateralRequest;
    mapping(bytes32 requestId => bool) private isCollateralDetailsAvailable;
    mapping(address => mapping(uint64 => uint256)) public lastNonceUsed;

    /// @dev the array of borrowers
    address[] private borrowers;

    CCIPRequestHandler ccipRequestHandler;

    ///////////////////////
    // Immutable variables
    ///////////////////////

    /// @dev address of the stable coin which the protocol supports

    address private immutable i_stableCoinAddress;
    uint256 ethChainId = 11155111; // for sepolia now

    ///////////////////
    // Constants
    ///////////////////

    /// @dev Precision factor used in price feed calculations
    /// @notice This constant defines the additional precision (1e10) to scale price data for accurate calculations

    uint256 private constant ADDITIONAL_PRICEFEED_PRECISION = 1e10;

    /// @dev The precision factor used for calculations involving token amounts or decimals
    /// @notice This constant defines the precision (1e18) for scaling values to match token precision or to avoid precision loss

    uint256 private constant PRECISION = 1e18;

    /// @dev The Loan-to-Value (LTV) ratio used in the system
    /// @notice This constant defines the LTV ratio as 75%, represented with 18 decimal places (75e16)

    uint256 private constant LTV = 75e16;

    /// @notice Penalty threshold for triggering liquidation.
    /// @dev Represents 80% (0.8 * 1e18 precision) threshold; if collateral value falls below this, the loan can be liquidated.

    uint256 private constant LIQUIDATION_THRESHOLD = 80e16;

    uint256 private constant LIQUIDATION_PENALTY = 5e16; // 5% penalty on LIQUIDATION_PENALTY

    uint64 public constant ACTION_COMMUNICATION_ID = 0;
    uint64 public constant REQUEST_COMMUNICATION_ID = 1;
    uint64 public constant RESPONSE_COMMUNICATION_ID = 2;

    //////////////////////////
    // public state variables
    //////////////////////////

    /// @notice the approved list of tokens the contract accept to trade

    address[] public s_tokenAddressesList;

    /// @notice the total amount of loan given by the protcol in USD

    uint256 public totalBorrowed;

    address public interestRateModelAddress;

    IVault vault;

    CrossChainMessageSender crossChainMessageSender;

    CrossChainMessageReceiver crossChainMessageReceiver;

    address linkToken;

    IRegistry registry;

    IGlobalStateManager GSM;

    CCIPResponseHandler ccipResponseHandler;

    mapping(uint64 chainId => bool isAllowed) private s_AllowedChains;

    enum Request {
        REQUEST_COLLATERAL_INFORMATION_FOR_USER
    }

    enum Response {
        RESPONSE_COLLATERAL_INFORMATION_FOR_USER
    }

    string private constant ETH_CONTRACT_RECEIVER_ADDRESS =
        "sepoliaReceiverAddress";

    ////////////////////
    // Events
    ////////////////////

    event CollateralRequestStillPending();

    /// @notice Emitted when a borrower repays their loan.
    /// @param user The address of the borrower.
    /// @param token The address of the token used for the loan.
    /// @param totalAmount The total amount repaid (principal + interest).
    /// @param interestPaid The portion of the repayment that is interest.
    /// @param principalRepaid The portion of the repayment that goes toward the original loan amount.

    event LoanRepaid(
        address indexed user,
        address indexed token,
        uint256 totalAmount,
        uint256 interestPaid,
        uint256 principalRepaid
    );

    /// @notice Emitted when collateral is released back to the user after loan repayment or liquidation.
    /// @param user The address of the user receiving the collateral.
    /// @param token The token address of the released collateral.
    /// @param amount The amount of collateral released.

    event CollateralReleased(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    /// @notice Emitted when a user withdraws their collateral.
    /// @param user The address of the user who withdrew collateral.
    /// @param token The address of the token being withdrawn.
    /// @param amount The amount of collateral withdrawn.

    event CollateralWithdrawed(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    /**
     *
     *  @dev Emitted when a user deposits liquidity into the protocol
     *
     *  Note that the `tokenAddress` has to be a valid addresss supported by the procool
     *  and the `amountDeposited`should be above zero
     */

    event LiquidityDeposited(
        address indexed user,
        address indexed tokenAddress,
        uint256 amountDeposited,
        uint256 lpTokenMinted
    );

    event DepositCollateralInitiated(
        address indexed user_,
        uint256 chainId,
        uint64 tokenId,
        uint64 destinationChainSelector,
        uint256 amount
    );

    /// @dev Emitted when a user withdraws a deposit
    /// @param user The address of the user who withdrew the deposit
    /// @param tokenAddress The address of the token being withdrawn
    /// @param amount The amount of the token withdrawn

    event DepositWithdrawn(
        address indexed user,
        address indexed tokenAddress,
        uint256 amount
    );

    /// @dev Emitted when a user deposits collateral
    /// @param user The address of the user who deposited the collateral
    /// @param tokenAddress The address of the token used as collateral

    event CollateralDeposited(
        address indexed user,
        address indexed tokenAddress,
        uint256 amountOfCollaterlDeposited
    );

    /// @dev Emitted when a user borrows a loan
    /// @param user The address of the user who borrowed the loan
    /// @param token The address of the token associated with the loan
    /// loanDetails The detailed information of the loan (e.g., amount, collateral, etc.)

    event LoanBorrowed(
        address indexed user,
        address indexed token,
        LoanDetails indexed loadnDetails,
        uint256 amount
    );

    /// @dev Emitted when a user burns LP tokens
    /// @param user The address of the user who burned the lp tokens
    /// @param amount The amount of LP tokens the user burned

    event LpTokensBurned(address indexed user, uint256 amount);

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

    event TokenTransferInitiated(
        address indexed user,
        uint64 tokenId,
        uint64 destinationChainSelector,
        uint256 amount
    );
    event TokensReceivedFromCrossChain(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    ////////////////////
    // Modififer
    ////////////////////

    /// @dev this prevent the user from passing zero value to the contract
    ///

    modifier isGreaterThanZero(uint256 amount) {
        if (amount == 0) {
            revert LendingPoolContractErrors
                .LendingPoolContract__AmountShouldBeGreaterThanZero();
        }
        _;
    }

    /// @dev this prevent the user from depositing money from chains that is not supported on this contract

    modifier isTokenApprovedByTheContract(uint64 tokenId) {
        if (s_priceFeed[tokenId] == address(0)) {
            revert LendingPoolContractErrors
                .LendingPoolContract__TokenIsNotAllowedToDeposit();
        }
        _;
    }

    modifier isChainAllowed(uint64 chainId) {
        if (s_AllowedChains[chainId] != true) {
            revert LendingPoolContractErrors
                .LendingPoolContract__InvalidChainId();
        }
        _;
    }

    ////////////////////
    // Constructor
    ////////////////////
    /// @dev   this params that are passed through the contract are immutable
    /// @param tokenAddresses this is the token addresses that are recognized by the contract
    /// @param priceFeedAddresses this is the pricefeed addreses of the corresponding token addressses
    /// @param stableCoinAddress this is the stable coin address which is used in lending pegged against the us doller
    ///         meaning 1 stable coin == 1 $
    /// @param lpTokenAddress this is the addrsss of the lp token that is used to reward the users that provide the contract with the liquidity
    /// Note that the constructor throws an error if the length of the pricefeed address array is not equal to the token addresses array
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        uint64[] memory chainIds,
        address stableCoinAddress,
        address lpTokenAddress,
        address interestRateModelAddress_,
        address link_,
        address router_,
        address gsm,
        address registry_
    ) Ownable(msg.sender) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert LendingPoolContractErrors
                .LendingPoolContract__TokenAddressAndPriceFeedAddressMismatch(
                    tokenAddresses.length,
                    priceFeedAddresses.length
                );
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_borrowerIndex[uint64(i)] = 1e18;
            s_lastAccuralTime[uint64(i)] = block.timestamp;
            s_priceFeed[uint64(i)] = priceFeedAddresses[i];
            s_tokenAddressesList.push(tokenAddresses[i]);
            s_tokenAddresses[uint64(i)] = tokenAddresses[i];
            s_tokenId[tokenAddresses[i]] = uint64(i);
        }

        for (uint i = 0; i < chainIds.length; i++) {
            s_AllowedChains[chainIds[i]] = true;
        }
        interestRateModelAddress = interestRateModelAddress_;

        i_stableCoinAddress = stableCoinAddress;
        lpToken = lpTokenAddress;
        vault = IVault(address(new Vault(address(this), i_stableCoinAddress)));
        crossChainMessageSender = new CrossChainMessageSender(link_, router_);

        linkToken = link_;
        ccipRequestHandler = new CCIPRequestHandler(
            address(this),
            registry_,
            gsm,
            address(crossChainMessageSender)
        );
        ccipResponseHandler = new CCIPResponseHandler(
            address(this),
            registry_,
            address(ccipRequestHandler)
        );
        crossChainMessageReceiver = new CrossChainMessageReceiver(
            router_,
            address(ccipResponseHandler)
        );
        if (block.chainid == ethChainId) {
            GSM = IGlobalStateManager(gsm);
        }
        registry = IRegistry(registry_);
    }

    ////////////////////
    // Functions
    ////////////////////

    // EXTERNAL FUNCTIONS
    /**
     * @notice Allows users to deposit ERC20 tokens into the lending pool and receive LP tokens in return.
     * @dev This function securely transfers tokens from the user's account to the contract using `safeTransferFrom`,
     *      ensuring the user has approved the necessary funds. The function prevents reentrancy attacks using `nonReentrant`.
     *      The deposit amount must be greater than zero and the token must be allowed for deposits.
     *
     *      When the pool has zero liquidity (first deposit), the user receives LP tokens equal to the deposit amount.
     *      For subsequent deposits, the number of LP tokens minted is proportional to the deposit amount relative to the
     *      total liquidity and the total supply of LP tokens using the formula:
     *
     *      - If the pool is empty or the deposit equals current liquidity:
     *        `mintAmount = amount`
     *      - Otherwise:
     *        `mintAmount = (amount * totalSupplyOfLpToken) / currentTotalLiquidity`
     *
     * @param tokenId The tokenId of the ERC20 token to be deposited.
     * @param amount The amount of tokens to deposit.
     *
     * @custom:requirements
     * - The `amount` must be greater than zero.
     * - The `token` must be an allowed token for deposits.
     * - The user must have approved the contract to spend the specified `amount` of tokens.
     *
     * @custom:reverts
     * - `LendingPoolContract__AmountShouldBeGreaterThanZero` if the deposit amount is zero.
     * - `LendingPoolContract__TokenIsNotAllowedToDeposit` if the token is not allowed for deposits.
     *
     * @custom:emit LiquidityDeposited Emitted when a successful deposit occurs.
     */

    //  a particular note change the miniting amount as per the token, if not the user can deposit on any small token and gain large amount of lptokens in return
    function depositLiquidity(
        uint64 tokenId,
        uint256 amount
    )
        external
        payable
        isGreaterThanZero(amount)
        isTokenApprovedByTheContract(tokenId)
        nonReentrant
    {
        //safeTraansfer function is used instead of the normal transfer,it ensures that the user has approved necessery funds for the contract
        address tokenAddress = s_tokenAddresses[tokenId];
        vault.depositLiquidity(msg.sender, tokenAddress, amount);
        uint256 currentTotalLiquidity = s_liquidity[tokenId];
        uint256 totalSupplyOfLpToken = ILpToken(lpToken).totalSupply();
        uint256 amountOfLpTokensToMint;
        if (totalSupplyOfLpToken == 0 || currentTotalLiquidity == amount) {
            amountOfLpTokensToMint = amount;
        } else {
            amountOfLpTokensToMint =
                (amount * totalSupplyOfLpToken) /
                currentTotalLiquidity;
        }
        s_depositDetailsOfUser[block.chainid][msg.sender][tokenId] += amount;
        s_liquidity[tokenId] += amount;
        _mintLpTokens(msg.sender, amountOfLpTokensToMint);
        emit LiquidityDeposited(
            msg.sender,
            tokenAddress,
            amount,
            amountOfLpTokensToMint
        );
    }

    // DEPOSITING THE COLLATERAL FUNCTION

    /// @dev Allows a user to deposit collateral in the form of an ERC20 token into the contract.
    /// This function performs checks to ensure the amount is greater than zero and that the token is
    /// allowed for collateral deposits. The deposited amount is updated in both the user's collateral
    /// details and the total collateral for the token. Additionally, the token is safely transferred from
    /// the user's address to the contract address.
    ///
    /// @param tokenId The tokenId of the ERC20 token that the user is depositing as collateral.
    /// @param amount The amount of the ERC20 token that the user wishes to deposit as collateral.
    ///
    /// @notice This function emits a `CollateralDeposited` event once the deposit is successfully made.
    /// The event contains the user's address, the token address, and the amount deposited.
    ///
    /// @dev The following conditions are verified before processing the deposit:
    /// - The deposit amount must be greater than zero, enforced by the `isGreaterThanZero(amount)` modifier.
    /// - The token being deposited must be one that is allowed for collateral, enforced by the `isTokenApprovedByTheContract(token)` modifier.
    /// - The function is protected against reentrancy attacks by the `nonReentrant` modifier.
    ///
    /// @custom:security non-reentrant Ensures that the function cannot be called recursively.
    /// @custom:modifier isGreaterThanZero(amount) Validates that the deposit amount is greater than zero.
    /// @custom:modifier isTokenApprovedByTheContract(token) Ensures that the specified token is allowed for collateral deposit.

    function depositCollateral(
        uint64 tokenId,
        uint256 amount
    )
        external
        payable
        isGreaterThanZero(amount)
        isTokenApprovedByTheContract(tokenId)
        isChainAllowed(uint64(block.chainid))
        nonReentrant
    {
        uint64 destinationChainSelector = registry.getDestinationChainSelector(
            ethChainId
        );
        address tokenAddress = s_tokenAddresses[tokenId];
        vault.depositCollateral(msg.sender, tokenAddress, amount);

        if (ethChainId == block.chainid) {
            GSM.updateCollateralDetailsOfUser(
                block.chainid,
                msg.sender,
                tokenId,
                amount
            );
        } else {
            address receiver = registry.getAddress(
                block.chainid,
                ETH_CONTRACT_RECEIVER_ADDRESS
            );
            bytes memory data = abi.encode(
                CrossChainPayLoad({
                    actionType: ActionType.DEPOSIT_COLLATERAL,
                    chainId: block.chainid,
                    user: msg.sender,
                    crossChaintokenId: tokenId,
                    amountToTransfer: amount,
                    messageToTransfer: ""
                })
            );

            uint256 fees = crossChainMessageSender.getFee(
                receiver,
                data,
                destinationChainSelector,
                address(0),
                amount,
                false
            );
            if (msg.value < fees) {
                revert LendingPoolContractErrors
                    .LendingPoolContract__InsufficentFees();
            }
            (bool success, ) = payable(crossChainMessageSender).call{
                value: fees
            }("");
            if (!success) {
                revert LendingPoolContractErrors
                    .LendingPoolContract__TransferFailed();
            }
            sendCCIPMessageForDepositCollateral(
                block.chainid,
                msg.sender,
                tokenId,
                amount,
                receiver,
                destinationChainSelector,
                data
            );
        }

        emit CollateralDeposited(msg.sender, tokenAddress, amount);
    }

    /**
     * @notice Allows users to withdraw their deposited tokens from the lending pool.
     * @dev This function ensures the user has a sufficient deposit balance before proceeding with the withdrawal.
     *      It uses `safeTransfer` to securely transfer the tokens from the contract to the user.
     *      The function prevents reentrancy attacks using the `nonReentrant` modifier.
     *
     * @param tokenId The tokenId of the ERC20 token to be withdrawn.
     * @param amount The amount of tokens the user wishes to withdraw.
     *
     * Requirements:
     * - The `amount` must be greater than zero. (Enforced by `isGreaterThanZero` modifier)
     * - The `token` must be an allowed token for deposits. (Enforced by `isTokenApprovedByTheContract` modifier)
     * - The user must have a sufficient deposit balance to cover the withdrawal amount.
     *
     * Errors:
     * - `LendingPoolContract__AmountShouldBeGreaterThanZero` if the amount is zero.
     * - `LendingPoolContract__TokenIsNotAllowedToDeposit` if the token is not supported.
     * - `LendingPoolContract__InsufficentBalance` if the user attempts to withdraw more than their available balance.
     *
     * Events:
     * - Emits `DepositWithdrawn` upon a successful withdrawal.
     */

    function withdrawDeposit(
        uint64 tokenId,
        uint256 amount
    )
        external
        isGreaterThanZero(amount)
        isTokenApprovedByTheContract(tokenId)
        nonReentrant
    {
        address tokenAddress = s_tokenAddresses[tokenId];
        uint256 depositAmount = s_depositDetailsOfUser[block.chainid][
            msg.sender
        ][tokenId];
        if (depositAmount < amount) {
            revert LendingPoolContractErrors
                .LendingPoolContract__InsufficentBalance(amount, depositAmount);
        }
        s_depositDetailsOfUser[block.chainid][msg.sender][tokenId] -= amount;
        s_liquidity[tokenId] -= amount;
        vault.withdrawDeposit(msg.sender, tokenAddress, amount);
        emit DepositWithdrawn(msg.sender, tokenAddress, amount);
    }

    /**
     * @notice Burns a specified amount of LP tokens from the sender's balance.
     * @dev This function checks whether the sender has a sufficient balance of LP tokens
     *      before proceeding to burn the specified amount using the `_burnLpTokens` function.
     *      It reverts with a custom error if the sender has an insufficient balance.
     * @param amount The amount of LP tokens to be burned.
     *
     * Requirements:
     * - The `amount` must be greater than zero. (Enforced by `isGreaterThanZero` modifier)
     * - The sender must have at least `amount` of LP tokens.
     *
     * Errors:
     * - `LendingPoolContract__InsufficentLpTokenBalance` if the sender's balance is less than the specified amount.
     */

    function burn(uint256 amount) external isGreaterThanZero(amount) {
        uint256 balance = ILpToken(lpToken).balanceOf(msg.sender);
        if (balance < amount) {
            revert LendingPoolContractErrors
                .LendingPoolContract__InsufficentLpTokenBalance();
        }
        _burnLpTokens(msg.sender, amount);
        emit LpTokensBurned(msg.sender, amount);
    }

    /// @dev Allows a user to borrow a loan using their deposited collateral.
    /// This function performs several checks before proceeding with the loan:
    /// 1. Verifies that the requested loan amount is greater than zero.
    /// 2. Ensures that the token used for the loan is allowed for collateral deposit.
    /// 3. Checks if there is already an active loan for the user with the same token.
    /// 4. Validates whether the user has enough collateral to borrow the requested amount.
    /// 5. Updates the user's loan details, collateral balance, and transfers the loan amount to the user.
    ///
    /// The collateral available for lending is determined by the Loan-to-Value (LTV) ratio and is converted to USD
    /// for comparison to the loan amount. If the loan request exceeds the available collateral value, the function reverts.
    ///
    /// The _accuredInterest function will periodically update the global borrowerIndex for a specific token everytime some user takes the loan
    /// from the protocol, this way the protocol opitmizes the gas cost by checking it for every user and updating it
    /// If the loan is successfully granted:
    /// - Updates the user's loan details (amount borrowed, collateral used, due date, etc.).
    /// - Moves the collateral from the user's available collateral to their locked collateral balance.
    /// - Emits a `LoanBorrowed` event.
    ///
    /// @param token The address of the ERC20 token used as collateral for the loan.
    /// @param amount The amount of the loan in USD value that the user wants to borrow.
    ///
    /// @notice This function emits a `LoanBorrowed` event upon successful loan issuance, which records the user's
    /// address, the token used for collateral, the loan details, and the amount borrowed.
    ///
    /// @dev The following checks and operations are performed:
    /// - The amount must be greater than zero (checked via the `isGreaterThanZero` modifier).
    /// - The token must be allowed for collateral (checked via the `isTokenApprovedByTheContract` modifier).
    /// - The user's previous loan must be cleared, or else the request will be rejected.
    /// - The function ensures that the user has enough collateral to borrow the requested amount based on the LTV ratio.
    /// - Updates the loan details, including collateral used and due date. The collateral is moved from the available to locked balance.
    /// - The loan amount is transferred to the user in the form of a stablecoin.

    /// @custom:modifier isGreaterThanZero(amount) Ensures that the loan amount is greater than zero.
    /// @custom:modifier isTokenApprovedByTheContract(token) Ensures that the token is allowed to be used for collateral deposit.

    function borrowLoan(
        uint64 tokenId,
        uint256 amount
    ) external isGreaterThanZero(amount) isTokenApprovedByTheContract(tokenId) {
        address tokenAddress = s_tokenAddresses[tokenId];
        if (s_loanDetails[msg.sender][tokenId].amountBorrowedInUSDT > 0) {
            revert LendingPoolContractErrors.LendingPoolContract__LoanPending();
        }
        uint256 depositedCollateral = s_collateralDetails[msg.sender][tokenId];

        // Calculate the amount of collateral available for lending, considering the LTV ratio
        uint256 collateralAvailableForLending = (depositedCollateral * LTV) /
            PRECISION;
        uint256 collateralAvailableForLendingInUsd = getUsdValue(
            tokenId,
            collateralAvailableForLending
        );
        if (amount > collateralAvailableForLendingInUsd) {
            revert LendingPoolContractErrors
                .LendingPoolContract__NotEnoughCollateral();
        }
        if (!s_isBorrower[msg.sender][tokenId]) {
            borrowers.push(msg.sender);
            s_loanTokensForTheUser[msg.sender].push(tokenId);
            s_isBorrower[msg.sender][tokenId] = true;
        }
        totalBorrowed += amount;
        s_amountBorrowedInToken[tokenId] += getTokenAmountFromUsd(
            tokenId,
            amount
        );
        LoanDetails storage loan = s_loanDetails[msg.sender][tokenId];
        // Update the loan details: amount borrowed, collateral used, last update, and due date
        loan.amountBorrowedInUSDT += amount;
        loan.principalAmount += amount;
        loan.asset = tokenAddress;
        loan.collateralUsed = getTokenAmountFromUsd(tokenId, amount);
        loan.lastUpdate = block.timestamp;
        loan.dueDate = block.timestamp + 180 days;
        loan.token = i_stableCoinAddress;
        loan.userBorrowIndex = s_borrowerIndex[tokenId];
        //updating the other params
        s_collateralDetails[msg.sender][tokenId] -= depositedCollateral;
        s_lockedCollateralDetails[msg.sender][tokenId] += depositedCollateral;
        _accuredInterest(tokenId); //this accuredInterest will update the global value for the borrowerIndex for the particular token everytime a user takes loan from the contract
        vault.transferLoanAmount(msg.sender, amount);
        emit LoanBorrowed(msg.sender, tokenAddress, loan, amount);
    }

    /**
     * @notice Allows a borrower to repay their outstanding loan, either partially or in full.
     *
     * @dev This function facilitates the repayment of a loan by a borrower. Loans are recorded with
     *      both principal and interest components. Interest is calculated using a dynamic borrow index
     *      that simulates interest accumulation over time, and this index is updated before repayment.
     *
     *      Here's how the process works in this function:
     *
     *      1. Interest Accrual:
     *         First, we ensure the interest is up-to-date by calling `_accuredInterest(token)`.
     *         This updates the borrow index and ensures fairness in interest tracking.
     *
     *      2. Loan State Extraction:
     *         We fetch the current loan details of the caller for the specified token, including the
     *         principal amount borrowed and the borrow index snapshot saved during borrowing.
     *
     *      3. Scaled Loan Calculation:
     *         Using the current global `s_borrowerIndex[token]` and the user's stored index,
     *         we calculate how much the total owed amount has grown due to interest.
     *         This is done via: `scaledLoanAmount = principal * currentIndex / userIndex`.
     *
     *      4. Interest Breakdown:
     *         The difference between the scaled amount and the original principal is the interest accrued.
     *         This interest must be paid first before reducing the principal.
     *
     *      5. Repayment Handling:
     *         - If the user repays less than the interest owed, the entire payment goes to interest.
     *         - If they repay more, excess goes to reducing the principal.
     *
     *      6. Loan Update:
     *         The loan record is updated accordingly. If the full amount is repaid, the collateral
     *         that was locked is released back to the user.
     *
     *      7. Emission:
     *         Two events are emitted:
     *         - `LoanRepaid` for tracking how much was paid, how much went to interest, and how much to principal.
     *         - `CollateralReleased` if the entire loan was cleared.
     *
     * @param tokenId The ERC20 token id representing the borrowed asset (usually a stablecoin like USDT or USDC).
     * @param amount The amount the borrower wants to repay.
     *
     * @custom:example
     * Suppose Alice borrowed 100 USDT using 150 USDT worth of ETH as collateral.
     * After 1 month, her total debt (due to interest) is 110 USDT.
     * - If she repays 50 USDT, 10 goes to interest, 40 reduces her principal (now 60 USDT).
     * - If she repays 110 USDT, her debt is cleared and her ETH collateral is unlocked.
     * - If she tries to repay more than 110 USDT, the function reverts (overpayment not allowed).
     *
     * @custom:reverts If the repayment amount exceeds the total loan amount (principal + interest).
     * @custom:security Non-reentrant and amount/token validity enforced through modifiers.
     */

    function repayLoan(
        uint64 tokenId,
        uint256 amount
    )
        external
        isTokenApprovedByTheContract(tokenId)
        isGreaterThanZero(amount)
        nonReentrant
    {
        address tokenAddress = s_tokenAddresses[tokenId];
        LoanDetails storage loan = s_loanDetails[msg.sender][tokenId];
        uint256 principalLoanAmount = loan.amountBorrowedInUSDT;
        uint256 userBorrowIndex = loan.userBorrowIndex;
        uint256 scaledLoanAmount = (principalLoanAmount *
            s_borrowerIndex[tokenId]) / userBorrowIndex;
        uint256 interestAccrued = scaledLoanAmount - principalLoanAmount;
        uint256 interestPaidNow = 0;
        uint256 principalRepaid = 0;
        if (amount > scaledLoanAmount) {
            revert LendingPoolContractErrors
                .LendingPoolContract__LoanAmountExceeded();
        }

        vault.claimLoan(msg.sender, amount);
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
        totalBorrowed -= principalRepaid;
        _accuredInterest(tokenId);

        if (loan.amountBorrowedInUSDT == 0) {
            _releaseCollateral(msg.sender, tokenId);
            emit CollateralReleased(msg.sender, tokenAddress, amount);
        } else {
            loan.lastUpdate = block.timestamp;
            loan.userBorrowIndex = s_borrowerIndex[tokenId];
        }
        emit LoanRepaid(
            msg.sender,
            tokenAddress,
            amount,
            interestPaidNow,
            principalRepaid
        );
    }

    /**
     * @notice Allows a user to withdraw a specified amount of their deposited collateral.
     * @dev Checks if the user has enough collateral deposited before allowing the withdrawal.
     * Updates the user's and contract's collateral records and transfers the tokens back to the user.
     *
     * @param tokenId The address of the token to withdraw.
     * @param amount The amount of the token the user wants to withdraw.
     */

    function withdrawCollateral(
        uint64 tokenId,
        uint256 amount
    )
        external
        isTokenApprovedByTheContract(tokenId)
        isGreaterThanZero(amount)
        nonReentrant
    {
        if (s_collateralDetails[msg.sender][tokenId] < amount) {
            revert LendingPoolContractErrors
                .LendingPoolContract__InvalidRequestAmount();
        }
        s_collateralDetails[msg.sender][tokenId] -= amount;
        s_tokenCollateral[tokenId] -= amount;
        vault.transferCollateral(msg.sender, s_tokenAddresses[tokenId], amount);
        emit CollateralWithdrawed(
            msg.sender,
            s_tokenAddresses[tokenId],
            amount
        );
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
        address user,
        uint64 tokenId
    ) internal isTokenApprovedByTheContract(tokenId) nonReentrant {
        address tokenAddress = s_tokenAddresses[tokenId];
        LoanDetails storage loan = s_loanDetails[user][tokenId];
        uint256 loanAmount = loan.amountBorrowedInUSDT;
        if (loanAmount == 0) {
            revert LendingPoolContractErrors
                .LendingPoolContract__LoanIsNotActive();
        }
        uint256 collateralValueInUSD = getUsdValue(
            tokenId,
            loan.collateralUsed
        );
        uint256 liquidationValue = (loanAmount * LIQUIDATION_PENALTY) /
            PRECISION;
        if (collateralValueInUSD > liquidationValue && loan.penaltyCount < 2) {
            revert LendingPoolContractErrors
                .LendingPoolContract__NotLiquidatable();
        }
        s_amountBorrowedInToken[tokenId] -= loan.collateralUsed;
        s_liquidity[tokenId] += loan.collateralUsed;
        if (loanAmount > totalBorrowed) {
            totalBorrowed = 0;
        } else {
            totalBorrowed -= loanAmount;
        }
        delete s_isBorrower[user][tokenId];
        delete s_loanDetails[user][tokenId];
        delete s_lockedCollateralDetails[user][tokenId];
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
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        for (uint256 i = 0; i < borrowers.length; i++) {
            address borrower = borrowers[i];
            uint64[] memory tokens = s_loanTokensForTheUser[borrower];
            for (uint256 j = 0; j < tokens.length; j++) {
                LoanDetails storage loan = s_loanDetails[msg.sender][tokens[j]];
                uint256 collateralValueInUSD = getUsdValue(
                    tokens[j],
                    loan.collateralUsed
                );
                uint256 liquidationValue = (loan.amountBorrowedInUSDT *
                    LIQUIDATION_PENALTY) / PRECISION;
                if (
                    block.timestamp > loan.dueDate ||
                    collateralValueInUSD < liquidationValue
                ) {
                    return (true, abi.encode(borrower, tokens[j]));
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
    function performUpkeep(bytes calldata performData) external override {
        (address borrower, uint64 tokenId) = abi.decode(
            performData,
            (address, uint64)
        );
        LoanDetails storage loan = s_loanDetails[borrower][tokenId];

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
            liquidate(borrower, tokenId);
        }
    }

    // function

    ////////////////////
    // Internal
    ////////////////////

    // calculate the utilization ratio
    /**
     * @notice Releases the user's locked collateral if the loan is fully repaid.
     * @dev Reverts if the user still has an outstanding loan.
     * @param user The address of the borrower.
     * @param tokenId The address of the token used as collateral.
     */

    function _releaseCollateral(address user, uint64 tokenId) internal {
        LoanDetails storage loan = s_loanDetails[user][tokenId];
        if (loan.amountBorrowedInUSDT != 0) {
            revert LendingPoolContractErrors
                .LendingPoolContract__LoanStillPending();
        }
        s_amountBorrowedInToken[tokenId] -= loan.collateralUsed;
        s_lockedCollateralDetails[user][tokenId] -= loan.collateralUsed;
        s_collateralDetails[user][tokenId] += loan.collateralUsed;
    }

    /**
     * @notice Accrues the interest for a given token based on the time elapsed since the last accrual.
     * @dev This function calculates and updates the interest for borrowers by taking into account the
     * amount of time that has passed since the last interest accrual. It uses the current interest rate
     * for the token, adjusts it per second, and updates the borrower index accordingly.
     *
     * The function performs the following steps:
     * 1. Calculates the time elapsed since the last accrual.
     * 2. Retrieves the current annual interest rate for the token using the `_calculateInterestRate` function.
     * 3. Converts the annual interest rate into a per-second rate.
     * 4. Calculates the interest factor based on the time elapsed and the per-second rate.
     * 5. Updates the borrower index (`s_borrowerIndex[token]`) to reflect the accumulated interest.
     *
     * After accruing interest, the function updates the last accrual time (`s_lastAccuralTime[token]`)
     * to the current block timestamp.
     *
     * @param tokenId The address of the token for which interest needs to be accrued.
     */
    function _accuredInterest(uint64 tokenId) private {
        uint256 timeElapsed = block.timestamp - s_lastAccuralTime[tokenId];
        if (timeElapsed == 0) return;
        uint256 annualInterestRate = IInterestRateModel(
            interestRateModelAddress
        ).getInterestRate(tokenId);
        uint256 ratePerSecond = annualInterestRate / 365 days;
        uint256 interestFactor = ratePerSecond * timeElapsed;
        s_borrowerIndex[tokenId] +=
            (s_borrowerIndex[tokenId] * interestFactor) /
            1e18;
        s_lastAccuralTime[tokenId] = block.timestamp;
    }

    /**
     * @notice Mints LP tokens to a specified address based on the provided amount.
     * @dev This internal function ensures that the minting amount is greater than zero using the `isGreaterThanZero` modifier.
     *      It attempts to mint LP tokens using the `ILpToken(lpToken).mint` function. If the minting fails, it reverts with
     *      the `LendingPoolContract__LpTokenMintFailed` error.
     *      Additionally, it updates the user's LP token balance in `tokenDetailsofUser`.
     *
     * @param to The address that will receive the minted LP tokens.
     * @param amountToMint The amount of LP tokens to mint.
     *
     * @custom:requirements
     * - `amountToMint` must be greater than zero.
     * - The LP token minting function must succeed.
     *
     * @custom:reverts
     * - `LendingPoolContract__LpTokenMintFailed` if the minting process fails.
     */
    function _mintLpTokens(
        address to,
        uint256 amountToMint
    ) internal isGreaterThanZero(amountToMint) {
        if (!ILpToken(lpToken).mint(to, amountToMint)) {
            revert LendingPoolContractErrors
                .LendingPoolContract__LpTokenMintFailed();
        }
        s_tokenDetailsofUser[to] += amountToMint;
    }

    /**
     * @notice Burns a specified amount of LP tokens from a user's balance.
     * @dev This internal function calls the `burn` function of the LP token contract to destroy the specified amount of tokens.
     *      After burning the tokens, it updates the user's LP token balance in the `tokenDetailsofUser` mapping.
     *
     * @param user The address of the user whose LP tokens are being burned.
     * @param amount The amount of LP tokens to burn.
     *
     * @custom:requirements
     * - The user must have a sufficient LP token balance for the burn to succeed.
     * - The LP token contract must implement the `burn` function correctly.
     *
     * @custom:reverts
     * - Reverts if the `burn` function of the LP token contract fails.
     */

    function _burnLpTokens(address user, uint256 amount) internal {
        ILpToken(lpToken).burn(user, amount);
        s_tokenDetailsofUser[user] -= amount;
    }

    ///////////////////
    // getters
    ///////////////////
    /**
     * @notice Returns the address of the LP token contract.
     * @dev This is a view function that provides access to the LP token's contract address.
     *
     * @return The address of the LP token contract.
     */
    function getLpTokenAddress() public view returns (address) {
        return address(lpToken);
    }

    /**
     * @notice Returns the total liquidity available in the lending pool.
     * @dev This is a view function that provides the current total liquidity value.
     *
     * @return The total liquidity in the pool, represented in the respective token's smallest unit.
     */

    function getTotalLiquidityPerToken(
        uint64 tokenId
    ) public view returns (uint256) {
        return s_liquidity[tokenId];
    }

    /**
     * @notice Returns the deposited balance of a sp
     * ecific user for a given token.
     * @dev This is a view function that retrieves the user's deposit balance from the storage mapping `s_depositDetailsOfUser`.
     *
     * @param user The address of the user whose balance is being queried.
     * @param tokenId The address of the token for which the user's balance is requested.
     *
     * @return The user's deposited balance for the specified token.
     */

    function getUserBalance(
        address user,
        uint64 tokenId
    ) public view returns (uint256) {
        return s_depositDetailsOfUser[block.chainid][user][tokenId];
    }

    /**
     * @notice Calculates and returns the current value of one LP token in terms of the underlying asset.
     * @dev The value of one LP token is determined using the formula:
     *
     *      `valueOfLpToken = totalLiquidity / ILpToken(lpToken).totalSupply()`
     *
     *      This function assumes that the total supply of LP tokens is greater than zero to avoid division by zero errors.
     *
     * @return valueOflpToken The current value of one LP token in terms of the underlying asset.
     */

    function getValueOfLpToken() public view returns (uint256 valueOflpToken) {
        valueOflpToken = getTotalLiquidity() / ILpToken(lpToken).totalSupply();
    }

    /**
     * @notice Calculates the total value locked (TVL) in the protocol.
     * @dev This function iterates through the list of supported tokens and sums their USD equivalent
     *      value using the `getUsdValue` function. It provides an accurate measure of the protocol's
     *      total liquidity.
     * @return totalLiquidity The total value of all tokens locked in the protocol, denominated in USD.
     */

    function getTotalLiquidity() public view returns (uint256) {
        uint256 totalLiquidity = 0;
        for (uint256 i = 0; i < s_tokenAddressesList.length; i++) {
            totalLiquidity += getUsdValue(
                uint64(i),
                s_liquidity[s_tokenId[s_tokenAddressesList[i]]]
            );
        }
        return totalLiquidity;
    }

    /**
     * @notice Returns the USD value of a specified token amount using its price feed.
     * @dev This function fetches the latest token price from the associated Chainlink price feed
     *      and calculates the equivalent USD value. It assumes the price feed provides data in a
     *      standard format with appropriate decimals.
     * @param tokenId The address of the token whose USD value needs to be calculated.
     * @param amount The amount of the token for which the USD value is required.
     * @return The USD value of the specified token amount, with additional precision applied.
     *
     * Requirements:
     * - The token must have a valid price feed available in `s_priceFeed`.
     * - The price feed must return a valid and non-negative price.
     */
    function getUsdValue(
        uint64 tokenId,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeed[tokenId]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return
            ((uint256(price) * ADDITIONAL_PRICEFEED_PRECISION) * amount) /
            PRECISION;
    }

    /**
     * @notice Converts a USD value into the corresponding amount of tokens.
     * @dev This function retrieves the latest price feed for the specified token,
     * and uses it to calculate how much of the token corresponds to a given USD value.
     * The calculation uses the price feed data, and converts the USD value into
     * the token amount, factoring in the precision settings.
     *
     * @param tokenId The address of the token to convert.
     * @param usdValue The amount in USD to convert into the corresponding token amount.
     * @return The equivalent amount of the token for the given USD value.
     */

    function getTokenAmountFromUsd(
        uint64 tokenId,
        uint256 usdValue
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeed[tokenId]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price feed data");

        return
            (usdValue * PRECISION) /
            (uint256(price) * ADDITIONAL_PRICEFEED_PRECISION);
    }

    /**
     * @notice Returns the amount of collateral a user has deposited for a specific token.
     * @param tokenId The address of the token.
     * @return The amount of collateral deposited by the caller for the given token.
     */

    /**
     * @notice Returns the total amount of a specific token deposited as collateral by all users.
     * @param tokenId The address of the token.
     * @return The total amount of that token used as collateral across the platform.
     */

    function getCollateralPerToken(
        uint64 tokenId
    ) external view returns (uint256) {
        return s_tokenCollateral[tokenId];
    }

    /**
     * @notice Returns the total amount borrowed for a specific token.
     * @param tokenId The address of the token.
     * @return The total amount borrowed for the specified token.
     */

    function getTotalBorroweedForAToken(
        uint64 tokenId
    ) external view returns (uint256) {
        return s_amountBorrowedInToken[tokenId];
    }

    /**
     * @notice Retrieves the loan details of a specific user for a given token.
     * @param user The address of the user.
     * @param tokenId The address of the token used for the loan.
     * @return The loan details (amount borrowed, collateral used, etc.) of the user for the specified token.
     */

    function getLoanDetails(
        address user,
        uint64 tokenId
    ) public view returns (LoanDetails memory) {
        return s_loanDetails[user][tokenId];
    }

    function getPriceFeedAddress(uint64 tokenId) public view returns (address) {
        return s_priceFeed[tokenId];
    }

    function getBorrowerIndex(uint64 tokenId) public view returns (uint256) {
        return s_borrowerIndex[tokenId];
    }

    function getInterestRateModelAddress() public view returns (address) {
        return interestRateModelAddress;
    }

    function getVaultAddress() external view returns (address) {
        return address(vault);
    }

    ///////////////////
    // CCIP
    ///////////////////

    enum ActionType {
        TRANSFER,
        DEPOSIT,
        DEPOSIT_COLLATERAL,
        GET_COLLATERAL_DETAILS
    }

    struct CrossChainPayLoad {
        ActionType actionType;
        uint256 chainId;
        address user;
        uint64 crossChaintokenId;
        uint256 amountToTransfer;
        string messageToTransfer;
    }

    struct CrossChainRequestPayLoad {
        Request request;
        address user;
        uint256 chainId;
        uint64 crossChainTokenId;
        bytes32 requestId;
    }

    struct CrossChainResponsePayLoad {
        Response response;
        address user;
        uint256 chainId;
        uint64 crossChainTokenId;
        bytes32 requestId;
        uint256 amount;
    }

    function transferTokensFromOneChainToOtherChain(
        address receiver,
        uint64 destinationChainSelector,
        uint64 tokenId,
        uint256 amount,
        bool isLink,
        string memory message
    )
        external
        payable
        isTokenApprovedByTheContract(tokenId)
        isGreaterThanZero(amount)
        nonReentrant
    {
        uint256 userBalance = s_depositDetailsOfUser[block.chainid][msg.sender][
            tokenId
        ];
        if (userBalance < amount) {
            revert LendingPoolContractErrors
                .LendingPoolContract__InsufficentBalance(amount, userBalance);
        }

        bytes memory data = abi.encode(
            CrossChainPayLoad({
                actionType: ActionType.TRANSFER,
                chainId: uint64(block.chainid),
                user: msg.sender,
                crossChaintokenId: tokenId,
                amountToTransfer: amount,
                messageToTransfer: message
            })
        );
        address tokenAddress = s_tokenAddresses[tokenId];
        if (isLink) {
            uint256 fees = crossChainMessageSender.getFee(
                receiver,
                data,
                destinationChainSelector,
                tokenAddress,
                amount,
                true
            );

            IERC20(linkToken).safeTransferFrom(
                msg.sender,
                address(crossChainMessageSender),
                fees
            );
            s_depositDetailsOfUser[block.chainid][msg.sender][
                tokenId
            ] -= amount;

            vault.transferToken(
                tokenAddress,
                address(crossChainMessageSender),
                amount
            );

            crossChainMessageSender.sendViaLink(
                receiver,
                data,
                destinationChainSelector,
                tokenAddress,
                amount
            );
        } else {
            uint256 fees = crossChainMessageSender.getFee(
                receiver,
                data,
                destinationChainSelector,
                tokenAddress,
                amount,
                false
            );
            if (msg.value < fees) {
                revert LendingPoolContractErrors
                    .LendingPoolContract__InsufficentFees();
            }

            (bool success, ) = payable(crossChainMessageSender).call{
                value: fees
            }("");
            if (!success) {
                revert LendingPoolContractErrors
                    .LendingPoolContract__TransferFailed();
            }
            s_depositDetailsOfUser[block.chainid][msg.sender][
                tokenId
            ] -= amount;
            vault.transferToken(
                address(crossChainMessageSender),
                tokenAddress,
                amount
            );
            crossChainMessageSender.sendViaNativeToken(
                receiver,
                data,
                destinationChainSelector,
                tokenAddress,
                amount
            );
        }
        emit TokenTransferInitiated(
            msg.sender,
            tokenId,
            destinationChainSelector,
            amount
        );
    }

    function getFee(
        address receiver,
        uint64 tokenId,
        uint256 amount,
        bool isLink,
        uint64 destinationChainSelector,
        string memory message
    ) external view returns (uint256 fees) {
        bytes memory data = abi.encode(
            CrossChainPayLoad({
                actionType: ActionType.TRANSFER,
                chainId: uint64(block.chainid),
                user: msg.sender,
                crossChaintokenId: tokenId,
                amountToTransfer: amount,
                messageToTransfer: message
            })
        );
        fees = crossChainMessageSender.getFee(
            receiver,
            data,
            destinationChainSelector,
            s_tokenAddresses[tokenId],
            amount,
            isLink
        );
    }

    modifier onlyCCIPResponderCanCall() {
        if (msg.sender != address(ccipResponseHandler)) {
            revert LendingPoolContractErrors
                .LendingPoolContract__InvalidRequest();
        }
        _;
    }

    function receiveTokensFromOneChainToOther(
        bytes memory data
    ) external nonReentrant onlyCCIPResponderCanCall {
        CrossChainPayLoad memory payLoad = abi.decode(
            data,
            (CrossChainPayLoad)
        );
        address tokenAddress = s_tokenAddresses[payLoad.crossChaintokenId];
        if (tokenAddress == address(0)) {
            revert LendingPoolContractErrors
                .LendingPoolContract__TokenIsNotAllowedToDeposit();
        }
        IERC20(tokenAddress).safeTransferFrom(
            address(crossChainMessageReceiver),
            address(vault),
            payLoad.amountToTransfer
        );

        uint256 current = s_depositDetailsOfUser[block.chainid][payLoad.user][
            payLoad.crossChaintokenId
        ];

        uint256 updated = current + payLoad.amountToTransfer;

        s_depositDetailsOfUser[block.chainid][payLoad.user][
            payLoad.crossChaintokenId
        ] = updated;

        emit TokensReceivedFromCrossChain(
            payLoad.user,
            tokenAddress,
            payLoad.amountToTransfer
        );
    }

    function setReceiverAddress(address sender) external {
        crossChainMessageReceiver.allowListedSender(sender, true);
    }

    function getCrossChainMessageReceiverAddress()
        external
        view
        returns (address)
    {
        return address(crossChainMessageReceiver);
    }

    function getCrossChainMessageSenderAddress()
        external
        view
        returns (address)
    {
        return address(crossChainMessageSender);
    }

    function getTokenAddressFromTokenId(
        uint64 tokenId
    ) external view returns (address) {
        return s_tokenAddresses[tokenId];
    }

    function setallowListedSenders(address sender) external onlyOwner {
        if (sender == address(0)) {
            revert LendingPoolContractErrors
                .LendingPoolContract__InvalidRequest();
        }
        crossChainMessageReceiver.allowListedSender(sender, true);
    }

    // IMPLEMENTATION OF THE LENDING LOGIC OF THE CCIP
    // THE USER CAN DEPOSIT COLLATERAL ON ANY CHAIN AND THEN CAN TAKE LOAN ON ANY
    // OTHER CHAIN, THIS IMPLEMENTATION IS ONLY FOR THE CROSS CHAIN, THE SINGLE CHAIN LENIDNG IS ALREADY IMPLEMENTED, THE CROSS CHAIN LOGIC
    // FOR THE REPAYING AND THE LIQUIDATION WILL BE FOLLOWED AFTER THIS, THE COLLATERAL CANNOT BE TRANSFERED CROSS CHAIN
    // THE COLLATERAL CAN ONLY BE RELEASED TO WHATEVER THE CHAIN THE COLLATERAL DEPOSITED, NOT TO ANY OTHER CHAIN

    function sendCCIPMessageForDepositCollateral(
        uint256 chainId_,
        address user_,
        uint64 tokenId,
        uint256 amount,
        address receiver,
        uint64 destinationChainSelector,
        bytes memory data
    ) private {
        crossChainMessageSender.sendViaNativeToken(
            receiver,
            data,
            destinationChainSelector,
            address(0),
            amount
        );
        emit DepositCollateralInitiated(
            user_,
            chainId_,
            tokenId,
            destinationChainSelector,
            amount
        );
    }

    function setGSMAddress(address gsm) external onlyOwner {
        if (block.chainid == ethChainId) {
            ccipRequestHandler.setGSMAddress(gsm);
        }
    }

    function getCollateralDetailsOfUser(
        address user,
        uint64 tokenId
    ) external returns (uint256) {
        uint256 lastNonce = lastNonceUsed[user][tokenId];
        bytes32 requestId = keccak256(abi.encode(user, tokenId, lastNonce));
        if (isCollateralDetailsAvailable[requestId]) {
            return pendingCollateralRequest[requestId];
        } else {
            emit CollateralRequestStillPending();
            return 0;
        }
    }

    function requestCollateralDetailsOfUser(
        address user_,
        uint64 tokenId,
        uint256 chainId
    ) external {
        uint256 nonce = block.number;
        uint64 destinationChainSelector = registry.getDestinationChainSelector(
            chainId
        );
        lastNonceUsed[user_][tokenId] = nonce;
        bytes32 requestId_ = keccak256(abi.encode(user_, tokenId, nonce));

        if (block.chainid == ethChainId) {
            pendingCollateralRequest[requestId_] = GSM.getUserCollateralDetails(
                block.chainid,
                user_,
                tokenId
            );
            isCollateralDetailsAvailable[requestId_] = true;
        } else {
            address receiver = registry.getCrossChainAddress(
                registry.getDestinationChainSelector(chainId),
                "crossChainMessageReceiverAddress"
            );

            bytes memory data = abi.encode(
                REQUEST_COMMUNICATION_ID,
                CrossChainRequestPayLoad({
                    request: Request.REQUEST_COLLATERAL_INFORMATION_FOR_USER,
                    user: user_,
                    chainId: chainId,
                    crossChainTokenId: tokenId,
                    requestId: requestId_
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

    function updateCollateralDetailsCrossChain(
        bytes32 requestId,
        uint256 balance
    ) external onlyCCIPResponderCanCall {
        isCollateralDetailsAvailable[requestId] = true;
        pendingCollateralRequest[requestId] = balance;
    }

    function setAllowListedSenders(
        address sender_,
        bool allowed
    ) external onlyOwner {
        crossChainMessageReceiver.allowListedSender(sender_, allowed);
    }

    function getActionCommunicationId() external pure returns (uint64) {
        return ACTION_COMMUNICATION_ID;
    }

    function getRequestCommunicationId() external pure returns (uint64) {
        return REQUEST_COMMUNICATION_ID;
    }

    function getResponseCommunicationId() external pure returns (uint64) {
        return RESPONSE_COMMUNICATION_ID;
    }

    function setAllowedCallersFoCrossChainMessageSender(
        address sender,
        bool status
    ) external onlyOwner {
        if (sender == address(0)) {
            revert LendingPoolContractErrors
                .LendingPoolContract__InvalidAddress();
        }
        crossChainMessageSender.setAllowedCallers(sender, status);
    }

    function getCCIPRequestHanlderAddress() external view returns (address) {
        return address(ccipRequestHandler);
    }

    function getCCIPResponseHandlerAddress() external view returns (address) {
        return address(ccipResponseHandler);
    }

    receive() external payable {}
}
