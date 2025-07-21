// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LpToken} from "../src/tokens/LpTokenContract.sol";
import {StableCoin} from "../src/tokens/StableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILpToken} from "./interfaces/ILpToken.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AggregatorV3Interface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ILendingPoolContract} from "../src/interfaces/ILendingPoolContract.sol";
import {LendingPoolContractErrors} from "./errors/Errors.sol";
import {console} from "forge-std/console.sol";
import {Vault} from "./Vault.sol";
import {IVault} from "./interfaces/IVault.sol";
import {ICrossChainMessageSender} from "./ccip/interfaces/ICrossChainMessageSender.sol";
import {ICrossChainMessageReceiver} from "./ccip/interfaces/ICrossChainMessageReceiver.sol";
import {CrossChainMessageReceiver} from "./ccip/CrossChainMessageReceiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IGlobalStateManager} from "./interfaces/IGlobalStateManager.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";
import {IStateAggregator} from "./interfaces/IStateAggregator.sol";
import {ICCIPRequestHandler} from "../src/ccip/interfaces/ICCIPRequestHandler.sol";
import {ICCIPReceiver} from "../src/ccip/interfaces/ICCIPReceiver.sol";
import {LoanManager} from "./GSM/LoanManager.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ILiquidityContorller} from "../src/service/interfaces/ILiquidityController.sol";
import {ICollateralController} from "../src/service/interfaces/ICollateralController.sol";
import {ILoanController} from "../src/service/interfaces/ILoanController.sol";

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
    ILendingPoolContract,
    Initializable,
    OwnableUpgradeable
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

    // a funcitonality not in provision anymore

    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => uint256 amount))) s_depositDetailsOfUser;

    /// @dev Tracks loan details for each user per token
    /// @custom:structure mapping(user => mapping(tokenAddress => LoanDetails))

    mapping(address user => mapping(uint64 tokenId => LoanDetails loanDetails))
        private s_loanDetails;

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

    /// @notice Tracks the total amount borrowed for each token across all users.
    /// @dev Maps a token address to the cumulative borrowed amount in that token.

    mapping(uint64 tokenId => uint256 amountBorrowed)
        private s_amountBorrowedInToken;

    // mapping the tokenId to the tokenAddress

    mapping(uint64 tokenId => address tokenAddress) private s_tokenAddresses;
    mapping(address tokenAddress => uint64 tokenId) private s_tokenId;

    mapping(bytes32 requestId => uint256 amount)
        private pendingCollateralRequest;
    mapping(bytes32 requestId => bool) private isCollateralDetailsAvailable;
    mapping(address => mapping(uint64 => uint256)) public lastNonceUsed;

    ///////////////////////
    // Immutable variables
    ///////////////////////

    /// @dev address of the stable coin which the protocol supports

    address private i_stableCoinAddress;
    uint256 ethChainId = 11155111; // for sepolia now // replacing now with the anvil test chainId to test fuzzzing
    uint256 arbChainId = 421614;

    ///////////////////
    // Constants
    ///////////////////

    /// @dev Precision factor used in price feed calculations
    /// @notice This constant defines the additional precision (1e10) to scale price data for accurate calculations

    uint256 private constant ADDITIONAL_PRICEFEED_PRECISION = 1e10;

    /// @dev The Loan-to-Value (LTV) ratio used in the system
    /// @notice This constant defines the LTV ratio as 75%, represented with 18 decimal places (75e16)

    uint256 private constant LTV = 75e16;

    /// @notice Penalty threshold for triggering liquidation.
    /// @dev Represents 80% (0.8 * 1e18 precision) threshold; if collateral value falls below this, the loan can be liquidated.

    uint256 private constant LIQUIDATION_THRESHOLD = 80e16;

    /// @dev The precision factor used for calculations involving token amounts or decimals
    /// @notice This constant defines the precision (1e18) for scaling values to match token precision or to avoid precision loss

    uint256 private constant PRECISION = 1e18;

    uint64 public constant ACTION_COMMUNICATION_ID = 0;
    uint64 public constant RESPONSE_COMMUNICATION_ID = 1;

    //////////////////////////
    // public state variables
    //////////////////////////

    /// @notice the approved list of tokens the contract accept to trade

    address[] public s_tokenAddressesList;

    /// @notice the total amount of loan given by the protcol in USD

    uint256 public totalBorrowed;

    /// @notice Address of the interest rate model contract

    /// @notice Vault interface for asset management
    IVault vault;

    /// @notice Contract responsible for sending cross-chain messages
    ICrossChainMessageSender crossChainMessageSender;

    /// @notice Contract responsible for receiving cross-chain messages
    ICrossChainMessageReceiver crossChainMessageReceiver;

    /// @notice Address of the LINK token used for CCIP
    address linkToken;

    /// @notice Registry interface for managing protocol data
    IRegistry registry;

    /// @notice Interface to access global state variables
    IGlobalStateManager GSM;

    /// @notice CCIP receiver interface for handling incoming messages
    ICCIPReceiver ccipReceiver;

    /// @notice Aggregator for collecting and managing protocol state data
    IStateAggregator stateAggregator;

    /// @notice Mapping to track if a given chainId is allowed for cross-chain communication
    mapping(uint64 chainId => bool isAllowed) private s_AllowedChains;

    /// @notice Enum representing types of responses for user requests
    enum Response {
        /// @dev Response containing user's collateral information
        RESPONSE_COLLATERAL_INFORMATION_FOR_USER,
        /// @dev Response containing user's loan information
        RESPONSE_LOAN_INFORMATION_FOR_USER,
        RESPONSE_DEPOSIT_INFORMATION_FOR_USER,
        RESPONSE_LPTOKEN_UPDATE,
        RESPONSE_SET_INITAL_PARAMS
    }

    ICCIPRequestHandler ccipRequestHandler;
    /// @notice Constant string storing the receiver address for Ethereum Sepolia network
    string private constant ETH_CONTRACT_RECEIVER_ADDRESS =
        "sepoliaReceiverAddress";

    /// @notice Token ID used to represent Ethereum in cross-chain context
    uint64 ethTokenId = 0;

    ILiquidityContorller liquidityController;
    ICollateralController collateralController;
    ILoanController loanController;
    ////////////////////
    // Events
    ////////////////////

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
        LoanManager.LoanDetails indexed loadnDetails,
        uint256 amount
    );

    /// @dev Emitted when a user burns LP tokens
    /// @param user The address of the user who burned the lp tokens
    /// @param amount The amount of LP tokens the user burned

    event LpTokensBurned(address indexed user, uint256 amount);

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

    bool private initialized;

    function initialize(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        uint64[] memory chainIds,
        address stableCoinAddress,
        address lpTokenAddress,
        address link_,
        address gsm,
        address registry_,
        address vaultAddress,
        address crossChainMessageSenderAddress,
        address ccipReceiverAddress,
        address ccipRequestHandlerAddress,
        address stateAggregatorAddress,
        address crossChainMessageReceiverAddress,
        address liquidityControllerAddress,
        address collateralControllerAddress,
        address loanControllerAddress
    ) public initializer {
        require(!initialized, "Already initialized");
        initialized = true;

        __Ownable_init(msg.sender);

        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert LendingPoolContractErrors
                .LendingPoolContract__TokenAddressAndPriceFeedAddressMismatch(
                    tokenAddresses.length,
                    priceFeedAddresses.length
                );
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_lastAccuralTime[uint64(i)] = block.timestamp;
            s_priceFeed[uint64(i)] = priceFeedAddresses[i];
            s_tokenAddressesList.push(tokenAddresses[i]);
            s_tokenAddresses[uint64(i)] = tokenAddresses[i];
            s_tokenId[tokenAddresses[i]] = uint64(i);
        }

        for (uint i = 0; i < chainIds.length; i++) {
            s_AllowedChains[chainIds[i]] = true;
        }

        i_stableCoinAddress = stableCoinAddress;
        lpToken = lpTokenAddress;

        vault = IVault(vaultAddress);
        crossChainMessageSender = ICrossChainMessageSender(
            crossChainMessageSenderAddress
        );
        linkToken = link_;
        stateAggregator = IStateAggregator(stateAggregatorAddress);
        ccipRequestHandler = ICCIPRequestHandler(ccipRequestHandlerAddress);
        ccipReceiver = ICCIPReceiver(ccipReceiverAddress);
        crossChainMessageReceiver = ICrossChainMessageReceiver(
            crossChainMessageReceiverAddress
        );
        liquidityController = ILiquidityContorller(liquidityControllerAddress);
        collateralController = ICollateralController(
            collateralControllerAddress
        );
        loanController = ILoanController(loanControllerAddress);
        console.log("reached here");
        if (block.chainid == ethChainId) {
            GSM = IGlobalStateManager(gsm);
        } else {
            stateAggregator.setAuthorizedUpdators(address(ccipReceiver), true);
            stateAggregator.setAuthorizedReadors(address(this), true);
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

    //  the token id of eth is always zero
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
        liquidityController.depositController{value: msg.value}(
            s_tokenAddresses[tokenId],
            tokenId,
            msg.sender,
            amount
        );
    }

    // DEPOSITING THE COLLATERAL FUNCTION

    /**
     * @notice Allows a user to deposit a specified amount of an ERC20 token as collateral.
     * @dev
     * This function:
     * - Verifies that the deposit amount is greater than zero.
     * - Ensures the specified token is allowed by the contract for collateral.
     * - Confirms that the call is coming from an allowed chain.
     * - Safely transfers the token from the user to the Vault contract.
     *
     * On Ethereum mainnet:
     * - Updates the Global State Manager (GSM) with the user's updated collateral amount.
     * - Mirrors the user's collateral update to a remote chain (e.g., Arbitrum) via the GSM using the registry.
     *
     * On other chains:
     * - Encodes a cross-chain message payload using CCIP to notify the Ethereum mainnet about the deposit.
     * - Calculates the required fee for sending the CCIP message.
     * - Reverts if the sent `msg.value` is less than the required CCIP fee.
     * - Sends the CCIP message using the `sendCCIPMessage()` function to synchronize state on Ethereum.
     *
     * Emits a `CollateralDeposited` event on successful deposit.
     *
     * @param tokenId The internal token ID that represents the ERC20 token being deposited.
     * @param amount The amount of the token to be deposited by the user as collateral.
     *
     * @notice This function will fail if:
     * - The `amount` is zero or less.
     * - The `tokenId` does not correspond to an approved token.
     * - The chain calling the function is not registered as allowed.
     * - There are insufficient CCIP fees provided in `msg.value` (for non-Ethereum chains).
     * - The transfer of native fees to the `crossChainMessageSender` fails.
     *
     * @notice The function is chain-aware:
     * - On Ethereum: performs direct GSM updates and mirrors them to the remote chain (e.g., Arbitrum).
     * - On other chains: sends CCIP message to Ethereum to update global state.
     *
     * @custom:modifiers
     * - `isGreaterThanZero(amount)`: Ensures the amount is greater than zero.
     * - `isTokenApprovedByTheContract(tokenId)`: Validates the token is whitelisted.
     * - `isChainAllowed(block.chainid)`: Verifies the current chain is permitted for interaction.
     * - `nonReentrant`: Prevents reentrancy attacks.
     *
     * @custom:security non-reentrant Ensures the function cannot be re-entered during execution.
     *
     * emit: CollateralDeposited Emitted after a successful deposit with the user's address, token address, and amount.
     */

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
        collateralController.depositCollateral{value: msg.value}(
            s_tokenAddresses[tokenId],
            tokenId,
            msg.sender,
            amount
        );
    }

    /**
     * @notice Retrieves the collateral amount a user has deposited for a specific token on a given chain.
     * @param chainId The chain ID where the collateral was deposited.
     * @param user The address of the user whose collateral details are being queried.
     * @param tokenId The ID of the token for which collateral information is requested.
     * @return The amount of collateral the user has deposited for the specified token.
     * @dev Uses GSM on Ethereum mainnet and StateAggregator on other chains.
     */

    function getCollateralDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256) {
        return
            block.chainid == ethChainId
                ? GSM.getUserCollateralDetails(chainId, user, tokenId)
                : stateAggregator.readCollateralDetailsOfUser(
                    chainId,
                    user,
                    tokenId
                );
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
        payable
        isGreaterThanZero(amount)
        isTokenApprovedByTheContract(tokenId)
        nonReentrant
    {
        liquidityController.withDrawController(
            s_tokenAddresses[tokenId],
            msg.sender,
            tokenId,
            amount
        );
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

    // here the reward is not getting transfered to the user before burning and it need to be addressed

    function burn(uint256 amount) external isGreaterThanZero(amount) {
        uint256 balance = ILpToken(lpToken).balanceOf(msg.sender);
        if (balance < amount) {
            revert LendingPoolContractErrors
                .LendingPoolContract__InsufficentLpTokenBalance();
        }
        _burnLpTokens(msg.sender, amount);
        emit LpTokensBurned(msg.sender, amount);
    }

    /**
     * @notice Allows a user to borrow a loan against their deposited collateral.
     *
     * This function lets users borrow a specified USD-denominated amount, backed by their previously deposited ERC20
     * collateral. It validates the borrower's collateral against a pre-defined Loan-to-Value (LTV) ratio to ensure
     * safe lending practices and mitigates risks for the protocol.
     *
     * The function supports cross-chain state updates using CCIP (Cross-Chain Interoperability Protocol). On non-Ethereum
     * chains, it encodes loan information and forwards it to a receiver contract on Ethereum for state synchronization.
     * On Ethereum, it updates the Global State Manager directly and optionally mirrors the loan state to Arbitrum.
     *
     * ### Example Usage:
     * - User has deposited 1 ETH as collateral on Ethereum.
     * - Let's assume ETH is worth $3,000 and the LTV is 75%.
     * - The maximum loan amount the user can borrow is $2,250.
     * - The user calls `borrowLoan(1, tokenIdOfETH, 2000)` to borrow $2,000 in stablecoin.
     *
     * @param collateralChainId The chain ID where the user has deposited their collateral.
     * @param tokenId The ID of the ERC20 token used as collateral.
     * @param amount The amount (in USD) the user wants to borrow.
     *
     * return Emits a `LoanBorrowed` event upon successful loan issuance, which includes:
     *         - The user's address
     *         - The token used as collateral
     *         - Loan details (including amount, duration, loan ID, etc.)
     *         - The borrowed amount in USD
     *
     * @dev Preconditions and internal process:
     * - Checks if the borrowing `amount` is greater than zero using the `isGreaterThanZero` modifier.
     * - Verifies that the `tokenId` is supported for borrowing using the `isTokenApprovedByTheContract` modifier.
     * - Ensures that the collateral is sufficient using the LTV formula:
     *       collateralAvailable = (collateralDeposited * LTV) / PRECISION
     *   and converts it to USD for comparison.
     * - Maintains a borrower record and associates the loan to the user.
     * - Generates and stores a `LoanDetails` struct for the loan with unique loan ID.
     * - On Ethereum:
     *     - Directly updates the `GlobalStateManager (GSM)`.
     *     - Sends a mirrored update to Arbitrum using the `registry`.
     * - On other chains:
     *     - Encodes loan data and sends it to the Ethereum chain via `crossChainMessageSender` using CCIP.
     * - Transfers the loan amount in stablecoin to the user from the internal vault.
     * - Updates the global borrower index for interest tracking using `_accuredInterest`.
     *
     * @custom:modifier isGreaterThanZero(amount) Ensures the loan amount requested is greater than zero.
     * @custom:modifier isTokenApprovedByTheContract(tokenId) Ensures the token is supported for borrowing.
     * @custom:modifier isChainAllowed(chainId) Confirms the current chain is supported by the protocol.
     * @custom:security non-reentrant Prevents reentrancy attacks.
     *
     * @notice The function requires the sender to pay a fee when sending cross-chain updates. If insufficient fees are sent, the transaction reverts.
     * @notice On Ethereum, loans are recorded via `GSM`. On other chains, loans are forwarded to Ethereum using CCIP for state synchronization.
     * @notice Loans are due in 180 days from the time of borrowing and tracked via `LoanDetails.dueDate`.
     *
     * @dev Reverts with:
     * - `LendingPoolContract__NotEnoughCollateral` if the collateral is insufficient for the requested loan.
     * - `LendingPoolContract__InsufficentFees` if the provided fee is less than the calculated cross-chain message cost.
     * - `LendingPoolContract__TransferFailed` if the fee payment fails during cross-chain message dispatch.
     */

    function borrowLoan(
        uint256 collateralChainId,
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
        loanController.borrowLoanController{value: msg.value}(
            msg.sender,
            s_tokenAddresses[tokenId],
            collateralChainId,
            tokenId,
            amount
        );
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
     * After 1 month, her total debt (due to interest) is 110 USDT.
     * - If she repays 50 USDT, 10 goes to interest, 40 reduces her principal (now 60 USDT).
     * - If she repays 110 USDT, her debt is cleared and her ETH collateral is unlocked.
     * - If she tries to repay more than 110 USDT, the function reverts (overpayment not allowed).
     *`
     * @custom:reverts If the repayment amount exceeds the total loan amount (principal + interest).
     * @custom:security Non-reentrant and amount/token validity enforced through modifiers.
     */

    function repayLoan(
        uint256 loanChainId,
        uint64 tokenId,
        uint256 amount,
        uint256 loanId
    )
        external
        payable
        isTokenApprovedByTheContract(tokenId)
        isGreaterThanZero(amount)
        nonReentrant
    {
        loanController.repayLoanController{value: msg.value}(
            msg.sender,
            s_tokenAddresses[tokenId],
            loanChainId,
            tokenId,
            amount,
            loanId
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
        payable
        isTokenApprovedByTheContract(tokenId)
        isGreaterThanZero(amount)
        nonReentrant
    {
        collateralController.withDrawCollateralController{value: msg.value}(
            msg.sender,
            s_tokenAddresses[tokenId],
            tokenId,
            amount
        );
    }

    // function

    ////////////////////
    // Internal
    ////////////////////

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
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256) {
        return
            block.chainid == ethChainId
                ? GSM.readDepositDetailsOfUser(chainId, user, tokenId)
                : stateAggregator.readDepositDetailsOfUser(
                    chainId,
                    user,
                    tokenId
                );
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
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId
    ) public view returns (LoanManager.LoanDetails memory) {
        return
            block.chainid == ethChainId
                ? GSM.readLoanDetailsOfUser(chainId, user, tokenId, loanId)
                : stateAggregator.readLoanDetailsOfUser(
                    chainId,
                    user,
                    tokenId,
                    loanId
                );
    }

    function getPriceFeedAddress(uint64 tokenId) public view returns (address) {
        return s_priceFeed[tokenId];
    }

    function getBorrowerIndex(uint64 tokenId) public returns (uint256) {
        return
            block.chainid == ethChainId
                ? GSM.getBorrowerIndex(tokenId)
                : stateAggregator.getBorrowerIndex(tokenId);
    }

    function getVaultAddress() external view returns (address) {
        return address(vault);
    }

    ///////////////////
    // CCIP
    ///////////////////

    /// @notice Enum representing the type of cross-chain action being performed.
    enum ActionType {
        /// @dev A simple token transfer across chains.
        TRANSFER,
        /// @dev A liquidity deposit operation from one chain to another.
        DEPOSIT_LIQUIDITY,
        WITHDRAW_LIQUIDITY,
        /// @dev A collateral deposit for lending/borrowing purposes across chains.
        DEPOSIT_COLLATERAL,
        WITHDRAW_COLLATERAL,
        /// @dev An indication that a loan has been taken on a different chain.
        LOAN_TAKEN,
        LOAN_REPAYMENT
    }

    struct CrossChainPayLoad {
        ActionType actionType; // ───────────────────────────────╮ Type of cross-chain operation (e.g., DEPOSIT, LOAN_TAKEN)
        uint256 chainId; //                                      │ Chain ID where the action originates
        address user; //                                         │ Address of the user initiating the action
        uint64 crossChaintokenId; //                             │ Token identifier on the destination chain
        uint256 amountToTransfer; //                             │ Amount involved in the action (e.g., collateral or loan)
        string messageToTransfer; //                             │ Optional human-readable message or memo
        bytes extraInformation; // ──────────────────────────────╯ Additional data payload (flexible)
    }

    struct CrossChainResponsePayLoad {
        Response response; // ───────────────────────────────╮ Response type identifier (e.g., SUCCESS, ERROR)
        address user; //                                     │ Address of the user the response is for
        uint256 chainId; //                                  │ Originating chain ID of the request
        uint64 crossChainTokenId; //                         │ Token ID used in the cross-chain context
        uint256 amount; //                                   │ Amount processed or returned in the response
        uint256 timeOfResponse; //                           │ Timestamp of when the response was generated
        string messageToTransfer; //                         │ Optional descriptive message returned
        bytes extraInformation; // ──────────────────────────╯ Any additional data sent back (metadata, logs, etc.)
    }

    /**
     * @notice Initiates a cross-chain token transfer from the current chain to a specified destination chain.
     *
     * @dev
     * This function supports two modes of fee payment:
     * - Using LINK tokens
     * - Using the native token of the current chain (e.g., ETH)
     *
     * It checks for:
     * - Approved token ID
     * - Positive transfer amount
     * - Sufficient user balance
     * - Appropriate fee payment depending on the mode
     * - Secure transfer via non-reentrancy
     *
     * The transfer payload is encoded into a `CrossChainPayLoad` struct and passed to the `crossChainMessageSender`
     * to relay the transfer request. The amount is deducted from the sender's balance, and tokens are moved to
     * the custody of the `crossChainMessageSender` for forwarding.
     *
     * @param receiver The recipient address on the destination chain.
     * @param destinationChainSelector The unique chain selector for the target chain (as used in CCIP).
     * @param tokenId The internal identifier of the token being transferred (mapped to ERC20 address).
     * @param amount The amount of tokens to be transferred.
     * @param isLink Indicates whether LINK tokens will be used to pay the cross-chain fee.
     * @param message Optional string message to be transferred along with the transaction.
     *
     * @custom:example
     * Suppose a user wants to transfer 100 USDC (tokenId: 2) from Ethereum (chainId: 1) to Polygon (chainSelector: 137):
     *
     * ```
     * transferTokensFromOneChainToOtherChain(
     *     0xAbcD...Ef12, // receiver on Polygon
     *     137,           // destinationChainSelector for Polygon
     *     2,             // tokenId mapped to USDC
     *     100e6,         // 100 USDC in smallest unit (6 decimals)
     *     true,          // Use LINK tokens for fee payment
     *     "Sending funds to my Polygon wallet"
     * );
     * ```
     *
     * The function:
     * - Encodes a `CrossChainPayLoad` with type `TRANSFER`
     * - Calculates the LINK fee
     * - Transfers the LINK fee and token amount to the cross-chain sender
     * - Emits a `TokenTransferInitiated` event
     *
     * @custom:security
     * - The function is protected against reentrancy via `nonReentrant`.
     * - Ensures sender has enough balance.
     * - Validates the fee sufficiency before attempting transfer.
     * - Only tokens approved by the contract are allowed via modifier.
     *
     * @custom:error LendingPoolContract__InsufficentBalance If the sender does not have enough balance to transfer.
     * @custom:error LendingPoolContract__InsufficentFees If the user sends less native token than required for the fee.
     * @custom:error LendingPoolContract__TransferFailed If the native token fee transfer fails.
     *
     * @custom:events Emits `TokenTransferInitiated` when the transfer is successfully initiated.
     */
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
                messageToTransfer: message,
                extraInformation: ""
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

            (bool success, ) = payable(address(crossChainMessageSender)).call{
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

    /**
     * @notice Estimates the cross-chain transfer fee for a given token, destination chain, and transfer method.
     *
     * @dev
     * This function creates a `CrossChainPayLoad` struct with type `TRANSFER` and encodes it.
     * It then queries the `crossChainMessageSender` to compute the required fee based on:
     * - The payload size
     * - Token address
     * - Amount being transferred
     * - Destination chain
     * - Whether LINK or native token is used for the fee
     *
     * The function does not perform any state changes and is view-only.
     *
     * @param receiver The destination address on the target chain.
     * @param tokenId The internal identifier for the token to be transferred.
     * @param amount The amount of tokens to be transferred.
     * @param isLink Whether LINK tokens will be used to pay the fee (true) or native token (false).
     * @param destinationChainSelector The selector ID for the target chain (e.g., 137 for Polygon).
     * @param message Optional message to be included in the payload.
     *
     * @return fees The estimated cross-chain transfer fee in the specified fee payment mode.
     *
     * @custom:example
     * To estimate the fee for transferring 50 USDT (tokenId: 3) from Ethereum to Arbitrum:
     *
     * ```
     * uint256 fee = getFee(
     *     0xA1b2...C3d4, // Receiver on Arbitrum
     *     3,            // USDT token ID
     *     50e6,         // 50 USDT (6 decimals)
     *     true,         // Using LINK tokens
     *     42161,        // Arbitrum's chain selector
     *     "Transfering funds to Arbitrum"
     * );
     * ```
     *
     * @custom:notes
     * - The fee estimation depends on the payload size, destination chain gas costs, and token volatility.
     * - Always call this function before initiating a cross-chain transfer to avoid underpayment errors.
     */

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
                messageToTransfer: message,
                extraInformation: ""
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
        if (msg.sender != address(ccipReceiver)) {
            revert LendingPoolContractErrors
                .LendingPoolContract__InvalidRequest();
        }
        _;
    }

    /**
     * @notice Finalizes a cross-chain token transfer by receiving tokens sent from another chain.
     *
     * @dev
     * This function is triggered by a designated CCIP responder contract once a cross-chain
     * message is received. It performs the following:
     * - Decodes the payload (`CrossChainPayLoad`) received from the source chain.
     * - Verifies if the token is allowed for deposit.
     * - Transfers the tokens from the `crossChainMessageReceiver` contract to the protocol's vault.
     * - Updates the internal user deposit state on this chain.
     * - Emits a `TokensReceivedFromCrossChain` event.
     *
     * Requirements:
     * - Caller must be authorized via the `onlyCCIPResponderCanCall` modifier.
     * - Token must be approved (exist in `s_tokenAddresses` mapping).
     * - Vault and token transfers must succeed.
     *
     * @param data Encoded `CrossChainPayLoad` structure received from the source chain.
     * Should include:
     * - `user`: The address receiving the tokens.
     * - `crossChaintokenId`: The token identifier used in this protocol.
     * - `amountToTransfer`: Amount of tokens to credit to the user's balance.
     *
     * @custom:example
     * If a user on Ethereum sends 100 USDC to themselves on Polygon, the payload decoded will look like:
     * ```
     * CrossChainPayLoad({
     *     actionType: ActionType.TRANSFER,
     *     chainId: 1,                          // Ethereum
     *     user: 0x1234...abcd,                // User's wallet
     *     crossChaintokenId: 2,              // USDC token ID
     *     amountToTransfer: 100e6,           // 100 USDC (6 decimals)
     *     messageToTransfer: "Transfer",
     *     extraInformation: ""
     * });
     * ```
     * The vault will receive 100 USDC, and the user's deposit on Polygon will be increased accordingly.
     *
     * @custom:events
     * Emits {TokensReceivedFromCrossChain} on successful execution.
     *
     * @custom:security
     * - This function is protected by `nonReentrant` to prevent reentrancy exploits.
     * - Only callable by pre-authorized CCIP responder contract(s).
     */

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

    function getTotalLPTokensForTheUser(
        address user
    ) external view returns (uint256) {
        return
            block.chainid == ethChainId
                ? GSM.getLpTokensPerUser(user)
                : stateAggregator.getLpTokensPerUser(user);
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

    /**
     * @notice Sends a CCIP (Cross-Chain Interoperability Protocol) message using native token for gas fees.
     *
     * @dev
     * This function initiates a cross-chain message transfer using the `sendViaNativeToken` method
     * of the `crossChainMessageSender`. It uses the native token (e.g., ETH, MATIC) on the source chain
     * to pay for the gas on the destination chain. The token address is passed as `address(0)` since
     * no ERC20 token is being transferred as part of the message — only the payload and native fee.
     *
     * Requirements:
     * - The caller must ensure the required fee (in native tokens) is already handled outside this function.
     * - The `crossChainMessageSender` must be a trusted and initialized contract that handles CCIP logic.
     *
     * @param amount The amount of native token to be sent to the destination chain (used for token transfer or just gas).
     * @param receiver The address that will receive the message and tokens on the destination chain.
     * @param destinationChainSelector The CCIP chain selector ID representing the destination chain.
     * @param data The ABI-encoded payload to be sent to the destination chain.
     *
     * @custom:example
     * To send a payload to a user on Avalanche:
     * ```
     * sendCCIPMessage(
     *     1 ether,
     *     0xRecipientOnAvalanche,
     *     0xa86a, // Avalanche chain selector
     *     abi.encode(payload)
     * );
     * ```
     *
     * @custom:note
     * - This is a private utility function intended to abstract out repeated CCIP logic.
     * - If tokens are being transferred along with data, consider using the token address instead of `address(0)`.
     */

    function sendCCIPMessage(
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
    }

    function setGSMAddress(address gsm) external onlyOwner {
        if (block.chainid == ethChainId) {
            ccipRequestHandler.setGSMAddress(gsm);
        }
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

    function getCCIPReceiverAddress() external view returns (address) {
        return address(ccipReceiver);
    }

    function getAmountToRepay(
        uint256 loanChainId,
        uint64 tokenId,
        uint256 loanId
    ) public returns (uint256 scaledLoanAmount) {
        bool chainIdentififer = block.chainid == ethChainId;
        LoanManager.LoanDetails memory loan = chainIdentififer
            ? GSM.readLoanDetailsOfUser(
                loanChainId,
                msg.sender,
                tokenId,
                loanId
            )
            : stateAggregator.readLoanDetailsOfUser(
                loanChainId,
                msg.sender,
                tokenId,
                loanId
            );
        uint256 principalLoanAmount = loan.amountBorrowedInUSDT;
        uint256 userBorrowIndex = loan.userBorrowIndex;
        scaledLoanAmount =
            (principalLoanAmount *
                (
                    chainIdentififer
                        ? GSM.getBorrowerIndex(tokenId)
                        : stateAggregator.getBorrowerIndex(tokenId)
                )) /
            userBorrowIndex;
    }

    function getStableCoinAddress() external view returns (address) {
        return i_stableCoinAddress;
    }

    receive() external payable {}
}
