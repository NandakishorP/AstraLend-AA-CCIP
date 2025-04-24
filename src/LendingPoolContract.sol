// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {StableCoin} from "../src/StableCoin.sol";
import {LpToken} from "../src/LpTokenContract.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILpToken} from "./interfaces/ILpToken.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AggregatorV3Interface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
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
contract LendingPoolContract is ReentrancyGuard {
    ////////////////////
    // Using directives
    ////////////////////
    using SafeERC20 for IERC20;
    ////////////////////
    // Errors
    ////////////////////
    error LendingPoolContract__TokenAddressAndPriceFeedAddressMismatch(
        uint256 tokenAddressLength,
        uint256 priceFeedAddressLength
    );
    error LendingPoolContract__NotEnoughLpTokensToBurn(
        uint256 amountofLpTokensProvided
    );
    error LendingPoolContract__InsufficentBalance(
        uint256 amount,
        uint256 availableAmount
    );
    error LendingPoolContract__NotEnoughCollateral(
        address user,
        address tokenAddress,
        uint256 availableAmount
    );
    error LendingPoolContract__LoanPending();
    error LendingPoolContract__TokenIsNotAllowedToDeposit(address token);
    error LendingPoolContract__AmountShouldBeGreaterThanZero();
    error LendingPoolContract__LpTokenMintFailed();
    error LendingPoolContract__InsufficentLpTokenBalance(
        uint256 availableBalance
    );
    ////////////////////
    // State Variable
    ////////////////////
    //private variables

    /// @dev Struct representing an active loan taken by a user
    struct LoanDetails {
        address token; // ───────────────────────────────╮ ERC20 token address borrowed by the user
        uint256 amountBorrowedInUSDT; //                 │ Amount borrowed, denominated in USDT (smallest unit: 6 decimals)
        uint256 collateralUsed; //                       │ Collateral amount locked by the user (in collateral token units)
        uint256 lastUpdate; //                           │ Timestamp of the last update to the loan state
        address asset; //                                | Address of the token in which user take the loan
        uint256 userBorrowIndex; //                      | The borrowerIndex of the contract when the user made any last update on the loan
        uint256 dueDate; // ─────────────────────────────╯ Timestamp when the loan repayment is due
        uint8 penalty; // ───────────────────────────────╮ Penalty percentage applied after due date (e.g., 5 = 5%)
        bool isLiquidated; // ───────────────────────────╯ True if the loan has been liquidated due to default
    }

    mapping(address token => uint256 borrowerIndexOfToken)
        public s_borrowerIndex;
    uint256 public s_lastAccuralTime;

    /// @dev mapping the token addresses to the pricefeed addresses
    mapping(address collateralTokenAddress => address priceFeedAddress)
        private s_priceFeed;

    /// @dev Mapping to track deposited token amounts per user
    /// @custom:structure mapping(user => mapping(token => amount))
    mapping(address => mapping(address => uint256))
        private s_depositDetailsOfUser;

    /// @dev Tracks loan details for each user per token
    /// @custom:structure mapping(user => mapping(tokenAddress => LoanDetails))
    mapping(address user => mapping(address tokenAddress => LoanDetails loanDetails))
        private s_loanDetails;

    /// @dev Stores the LP token balance of each user
    /// @custom:structure mapping(user => lpTokenAmount)
    mapping(address user => uint256 lpTokenAmount) private s_tokenDetailsofUser;
    /// @dev address of the lptoken contract
    address private lpToken;
    /// @dev the total liquidity locked in the protocol at the moment for a particular token
    mapping(address token => uint256 totaliquidityOfToken) private s_liquidity;

    /// @dev Tracks the total collateral deposited for each token
    /// @custom:structure mapping(token => totalCollateralAmount)
    mapping(address token => uint256 totalCollateralOfToken)
        private s_tokenCollateral;

    /// @dev Stores the collateral amount for each user per token
    /// @custom:structure mapping(user => mapping(token => collateralAmount))
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDetails;

    /// @dev Stores the locked collateral amount for each user per token
    /// @custom:structure mapping(user => mapping(token => lockedCollateralAmount))
    mapping(address user => mapping(address token => uint256 amount))
        private s_lockedCollateralDetails;

    /// @dev checking whether the user has any active loans
    mapping(address => bool) private s_isBorrower;
    /// @dev the array of borrowers

    mapping(address token => uint256 amountBorrowed)
        private s_amountBorrowedInToken;

    address[] private borrowers;

    ///////////////////////
    // Immutable variables
    ///////////////////////

    /// @dev address of the stable coin which the protocol supports
    address private immutable i_stableCoinAddress;

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

    //////////////////////////
    // public state variables
    //////////////////////////

    /// @notice the approved list of tokens the contract accept to trade
    address[] public s_tokenAddressesList;

    /// @notice the total amount of loan given by the protcol in USD
    uint256 public totalBorrowed;

    uint256 public baseInterestRate = 5e16;
    uint256 public maxInterestRate = 50e15;
    uint256 public kink = 0.7e18;

    ////////////////////
    // Events
    ////////////////////

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

    event LpTokensBurned(address indexed user, uint256 amount);

    ////////////////////
    // Modififer
    ////////////////////

    /// @dev this prevent the user from passing zero value to the contract
    ///
    modifier isGreaterThanZero(uint256 amount) {
        if (amount == 0) {
            revert LendingPoolContract__AmountShouldBeGreaterThanZero();
        }
        _;
    }

    /// @dev this prevent the user from depositing money from chains that is not supported on this contract
    modifier isTokenAllowedToDeposit(address token) {
        if (s_priceFeed[token] == address(0)) {
            revert LendingPoolContract__TokenIsNotAllowedToDeposit(token);
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
        address stableCoinAddress,
        address lpTokenAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert LendingPoolContract__TokenAddressAndPriceFeedAddressMismatch(
                tokenAddresses.length,
                priceFeedAddresses.length
            );
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_borrowerIndex[tokenAddresses[i]] = 1e18;
            s_lastAccuralTime[tokenAddresses[i]] = block.timestamp;
            s_priceFeed[tokenAddresses[i]] = priceFeedAddresses[i];
            s_tokenAddressesList.push(tokenAddresses[i]);
        }
        i_stableCoinAddress = stableCoinAddress;
        lpToken = lpTokenAddress;
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
     * @param token The address of the ERC20 token to be deposited.
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

    function depositLiquidity(
        address token,
        uint256 amount
    )
        external
        payable
        isGreaterThanZero(amount)
        isTokenAllowedToDeposit(token)
        nonReentrant
    {
        //safeTraansfer function is used instead of the normal transfer,it ensures that the user has approved necessery funds for the contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 currentTotalLiquidity = s_liquidity[token];
        uint256 totalSupplyOfLpToken = ILpToken(lpToken).totalSupply();
        uint256 amountOfLpTokensToMint;
        if (totalSupplyOfLpToken == 0 || currentTotalLiquidity == amount) {
            amountOfLpTokensToMint = amount;
        } else {
            amountOfLpTokensToMint =
                (amount * totalSupplyOfLpToken) /
                currentTotalLiquidity;
        }
        s_depositDetailsOfUser[msg.sender][token] += amount;
        s_liquidity[token] += amount;
        _mintLpTokens(msg.sender, amountOfLpTokensToMint);
        emit LiquidityDeposited(
            msg.sender,
            token,
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
    /// @param token The address of the ERC20 token that the user is depositing as collateral.
    /// @param amount The amount of the ERC20 token that the user wishes to deposit as collateral.
    ///
    /// @notice This function emits a `CollateralDeposited` event once the deposit is successfully made.
    /// The event contains the user's address, the token address, and the amount deposited.
    ///
    /// @dev The following conditions are verified before processing the deposit:
    /// - The deposit amount must be greater than zero, enforced by the `isGreaterThanZero(amount)` modifier.
    /// - The token being deposited must be one that is allowed for collateral, enforced by the `isTokenAllowedToDeposit(token)` modifier.
    /// - The function is protected against reentrancy attacks by the `nonReentrant` modifier.
    ///
    /// @custom:security non-reentrant Ensures that the function cannot be called recursively.
    /// @custom:modifier isGreaterThanZero(amount) Validates that the deposit amount is greater than zero.
    /// @custom:modifier isTokenAllowedToDeposit(token) Ensures that the specified token is allowed for collateral deposit.

    function depositCollateral(
        address token,
        uint256 amount
    )
        external
        payable
        isGreaterThanZero(amount)
        isTokenAllowedToDeposit(token)
        nonReentrant
    {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        s_collateralDetails[msg.sender][token] += amount;
        s_tokenCollateral[token] += amount;
        emit CollateralDeposited(msg.sender, token, amount);
    }

    /**
     * @notice Allows users to withdraw their deposited tokens from the lending pool.
     * @dev This function ensures the user has a sufficient deposit balance before proceeding with the withdrawal.
     *      It uses `safeTransfer` to securely transfer the tokens from the contract to the user.
     *      The function prevents reentrancy attacks using the `nonReentrant` modifier.
     *
     * @param token The address of the ERC20 token to be withdrawn.
     * @param amount The amount of tokens the user wishes to withdraw.
     *
     * Requirements:
     * - The `amount` must be greater than zero. (Enforced by `isGreaterThanZero` modifier)
     * - The `token` must be an allowed token for deposits. (Enforced by `isTokenAllowedToDeposit` modifier)
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
        address token,
        uint256 amount
    )
        external
        isGreaterThanZero(amount)
        isTokenAllowedToDeposit(token)
        nonReentrant
    {
        uint256 depositAmount = s_depositDetailsOfUser[msg.sender][token];
        if (depositAmount < amount) {
            revert LendingPoolContract__InsufficentBalance(
                amount,
                depositAmount
            );
        }
        s_depositDetailsOfUser[msg.sender][token] -= amount;
        s_liquidity[token] -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);
        emit DepositWithdrawn(msg.sender, token, amount);
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
            revert LendingPoolContract__InsufficentLpTokenBalance(balance);
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
    /// - The token must be allowed for collateral (checked via the `isTokenAllowedToDeposit` modifier).
    /// - The user's previous loan must be cleared, or else the request will be rejected.
    /// - The function ensures that the user has enough collateral to borrow the requested amount based on the LTV ratio.
    /// - Updates the loan details, including collateral used and due date. The collateral is moved from the available to locked balance.
    /// - The loan amount is transferred to the user in the form of a stablecoin.

    /// @custom:modifier isGreaterThanZero(amount) Ensures that the loan amount is greater than zero.
    /// @custom:modifier isTokenAllowedToDeposit(token) Ensures that the token is allowed to be used for collateral deposit.

    function borrowLoan(
        address token,
        uint256 amount
    ) external isGreaterThanZero(amount) isTokenAllowedToDeposit(token) {
        if (s_loanDetails[msg.sender][token].amountBorrowedInUSDT > 0) {
            revert LendingPoolContract__LoanPending();
        }
        uint256 depositedCollateral = s_collateralDetails[msg.sender][token];

        // Calculate the amount of collateral available for lending, considering the LTV ratio
        uint256 collateralAvailableForLending = (depositedCollateral * LTV) /
            PRECISION;
        uint256 collateralAvailableForLendingInUsd = getUsdValue(
            token,
            collateralAvailableForLending
        );
        if (amount > collateralAvailableForLendingInUsd) {
            revert LendingPoolContract__NotEnoughCollateral(
                msg.sender,
                token,
                collateralAvailableForLendingInUsd
            );
        }
        if (!s_isBorrower[msg.sender]) {
            borrowers.push(msg.sender);
            s_isBorrower[msg.sender] = true;
        }
        totalBorrowed += amount;
        s_amountBorrowedInToken[token] += getTokenAmountFromUsd(token, amount);
        LoanDetails storage loan = s_loanDetails[msg.sender][token];
        // Update the loan details: amount borrowed, collateral used, last update, and due date
        loan.amountBorrowedInUSDT += amount;
        loan.asset = token;
        loan.collateralUsed = getTokenAmountFromUsd(token, amount);
        loan.lastUpdate = block.timestamp;
        loan.dueDate = block.timestamp + 90 days;
        //updating the other params
        s_collateralDetails[msg.sender][token] -= depositedCollateral;
        s_lockedCollateralDetails[msg.sender][token] += depositedCollateral;

        IERC20(i_stableCoinAddress).safeTransfer(msg.sender, amount);
        emit LoanBorrowed(msg.sender, token, loan, amount);
    }

    function repayLoan(
        address token,
        uint256 amount
    )
        external
        isTokenAllowedToDeposit(token)
        isGreaterThanZero(amount)
        nonReentrant
    {}

    ////////////////////
    // Internal
    ////////////////////

    // calculate the utilization ratio

    function calculateUtilizationRatio(
        address assetClass
    ) internal view returns (uint256 utilizationRatio) {
        if (s_liquidity[assetClass] == 0) {
            return 0;
        }
        utilizationRatio =
            (s_amountBorrowedInToken[assetClass] * PRECISION) /
            s_liquidity[assetClass];
    }

    // calculating the interest rate

    function calculateInterestRate(
        address token
    ) public view returns (uint256) {
        uint256 utilizationRatio = calculateUtilizationRatio(token);
        uint256 interestRate;
        if (utilizationRatio < kink) {
            interestRate =
                baseInterestRate +
                ((maxInterestRate - baseInterestRate) * utilizationRatio) /
                kink;
        } else {
            interestRate =
                maxInterestRate +
                ((maxInterestRate * (utilizationRatio - kink)) /
                    (PRECISION - kink));
        }

        return interestRate;
    }

    function _accuredInterest(address token) public {
        uint256 timeElapsed = block.timestamp - lastAccuralTime;
        if (timeElapsed == 0) return;
        uint256 annualInterestRate = calculateInterestRate(token);
        uint256 ratePerSecond = annualInterestRate / 365 days;
        uint256 interestFactor = ratePerSecond * timeElapsed;
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
            revert LendingPoolContract__LpTokenMintFailed();
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
        address token
    ) public view returns (uint256) {
        return s_liquidity[token];
    }

    /**
     * @notice Returns the deposited balance of a specific user for a given token.
     * @dev This is a view function that retrieves the user's deposit balance from the storage mapping `s_depositDetailsOfUser`.
     *
     * @param user The address of the user whose balance is being queried.
     * @param token The address of the token for which the user's balance is requested.
     *
     * @return The user's deposited balance for the specified token.
     */

    function getUserBalance(
        address user,
        address token
    ) public view returns (uint256) {
        return s_depositDetailsOfUser[user][token];
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
                s_tokenAddressesList[i],
                s_liquidity[s_tokenAddressesList[i]]
            );
        }
        return totalLiquidity;
    }

    /**
     * @notice Returns the USD value of a specified token amount using its price feed.
     * @dev This function fetches the latest token price from the associated Chainlink price feed
     *      and calculates the equivalent USD value. It assumes the price feed provides data in a
     *      standard format with appropriate decimals.
     * @param token The address of the token whose USD value needs to be calculated.
     * @param amount The amount of the token for which the USD value is required.
     * @return The USD value of the specified token amount, with additional precision applied.
     *
     * Requirements:
     * - The token must have a valid price feed available in `s_priceFeed`.
     * - The price feed must return a valid and non-negative price.
     */
    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeed[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return
            ((uint256(price) * ADDITIONAL_PRICEFEED_PRECISION) * amount) /
            PRECISION;
    }

    function getTokenAmountFromUsd(
        address token,
        uint256 usdValue
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeed[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price feed data");

        return
            (usdValue * PRECISION) /
            (uint256(price) * ADDITIONAL_PRICEFEED_PRECISION);
    }
}
