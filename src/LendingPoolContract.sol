pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LpToken} from "../src/tokens/LpTokenContract.sol";
import {StableCoin} from "../src/tokens/StableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILpToken} from "./interfaces/ILpToken.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRWAValuation} from "./rwa/interfaces/IRWAValuation.sol";
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


contract LendingPoolContract is
    ReentrancyGuard,
    ILendingPoolContract,
    Initializable,
    OwnableUpgradeable
{


    using SafeERC20 for IERC20;
    struct LoanDetails {
        address token;
        uint256 amountBorrowedInUSDT;
        uint256 principalAmount;
        uint256 collateralUsed;
        uint256 lastUpdate;
        address asset;
        uint256 userBorrowIndex;
        uint256 interestPaid;
        uint256 liquidationPoint;
        uint256 dueDate;
        uint8 penaltyCount;
        bool isLiquidated;
    }
    mapping(uint64 tokenId => uint256) public s_lastAccuralTime;
    mapping(uint64 collateralTokenId => address priceFeedAddress)
        private s_priceFeed;

    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => uint256 amount))) s_depositDetailsOfUser;

    mapping(address user => mapping(uint64 tokenId => LoanDetails loanDetails))
        private s_loanDetails;

    address private lpToken;

    mapping(uint64 tokenId => uint256 totaliquidityOfToken) private s_liquidity;


    mapping(uint64 tokenId => uint256 totalCollateralOfToken)
        private s_tokenCollateral;


    mapping(address user => mapping(uint64 tokenId => uint256 amount))
        private s_collateralDetails;

    mapping(address user => mapping(uint64 tokenId => uint256 amount))
        private s_lockedCollateralDetails;

    mapping(uint64 tokenId => uint256 amountBorrowed)
        private s_amountBorrowedInToken;

    mapping(uint64 tokenId => RiskParams) private s_riskParams;
    address private s_lienRegistry;

    mapping(uint64 tokenId => address tokenAddress) private s_tokenAddresses;
    mapping(address tokenAddress => uint64 tokenId) private s_tokenId;

    mapping(bytes32 requestId => uint256 amount)
        private pendingCollateralRequest;
    mapping(bytes32 requestId => bool) private isCollateralDetailsAvailable;
    mapping(address => mapping(uint64 => uint256)) public lastNonceUsed;



    address private i_stableCoinAddress;
    // Declared `constant` so the values live in bytecode rather than storage.
    // As plain state variables their inline initialisers only ran in the
    // implementation's constructor, leaving them zero behind the proxy — which
    // made every `block.chainid == ethChainId` branch take the satellite-chain
    // path and revert on the unset state aggregator.
    // Assigned in `initialize`, NOT at declaration: this contract sits behind a
    // proxy, where declaration-site initialisers only ever run in the
    // implementation's constructor and leave the proxy's storage at zero.
    // Settable afterwards so a local deployment can use a chain id that does not
    // collide with a wallet's built-in networks.
    uint256 public ethChainId;
    uint256 public arbChainId;



    uint256 private constant ADDITIONAL_PRICEFEED_PRECISION = 1e10;

    uint256 private constant LTV = 75e16;

    uint256 private constant LIQUIDATION_THRESHOLD = 80e16;

    uint256 private constant PRECISION = 1e18;
    uint64 public constant ACTION_COMMUNICATION_ID = 0;
    uint64 public constant RESPONSE_COMMUNICATION_ID = 1;



    address[] public s_tokenAddressesList;

    uint256 public totalBorrowed;

    IVault vault;

    ICrossChainMessageSender crossChainMessageSender;

    ICrossChainMessageReceiver crossChainMessageReceiver;

    address linkToken;
    IRegistry registry;
    IGlobalStateManager GSM;
    ICCIPReceiver ccipReceiver;
    IStateAggregator stateAggregator;
    mapping(uint64 chainId => bool isAllowed) private s_AllowedChains;
    enum Response {
        RESPONSE_COLLATERAL_INFORMATION_FOR_USER,

        RESPONSE_LOAN_INFORMATION_FOR_USER,
        RESPONSE_DEPOSIT_INFORMATION_FOR_USER,
        RESPONSE_LPTOKEN_UPDATE,
        RESPONSE_SET_INITAL_PARAMS
    }

    ICCIPRequestHandler ccipRequestHandler;
    string private constant ETH_CONTRACT_RECEIVER_ADDRESS =
        "sepoliaReceiverAddress";
    uint64 ethTokenId = 0;
    ILiquidityContorller liquidityController;
    ICollateralController collateralController;
    ILoanController loanController;


    event LoanRepaid(
        address indexed user,
        address indexed token,
        uint256 totalAmount,
        uint256 interestPaid,
        uint256 principalRepaid
    );

    event CollateralReleased(
        address indexed user,
        address indexed token,
        uint256 amount
    );


    event CollateralWithdrawed(
        address indexed user,
        address indexed token,
        uint256 amount
    );

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

    event DepositWithdrawn(
        address indexed user,
        address indexed tokenAddress,
        uint256 amount
    );
    event CollateralDeposited(
        address indexed user,
        address indexed tokenAddress,
        uint256 amountOfCollaterlDeposited
    );

    event LoanBorrowed(
        address indexed user,
        address indexed token,
        LoanManager.LoanDetails indexed loadnDetails,
        uint256 amount
    );
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


    modifier isGreaterThanZero(uint256 amount) {
        if (amount == 0) {
            revert LendingPoolContractErrors
                .LendingPoolContract__AmountShouldBeGreaterThanZero();
        }
        _;
    }

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
        console.log("going to enter");
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
        // Defaults match the live testnets; `setChainIds` overrides them locally.
        ethChainId = 11155111;
        arbChainId = 421614;

        // Restored to the original chain-id gate on purpose. Keying this off
        // `gsm != address(0)` instead made the *satellite* pool hold a GSM
        // address that only exists on the hub's fork, so the cross-fork
        // liquidation test failed with "contract does not exist". A hub running
        // on a non-default chain id assigns it via `setGlobalStateManager`.
        if (block.chainid == 11155111) {
            GSM = IGlobalStateManager(gsm);
        }
        registry = IRegistry(registry_);
    }
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
     * @notice Registers a real-world asset as acceptable collateral.
     * @param valuationOracle An IRWAValuation, which satisfies
     *        AggregatorV3Interface — so it slots straight into s_priceFeed and
     *        every existing pricing path keeps working untouched.
     * @dev Assets were previously fixed by a loop in initialize with no way to
     *      add one afterwards. This is that missing path, restricted to RWA so
     *      the crypto asset set stays exactly as deployed.
     */
    function addRwaAsset(
        uint64 tokenId,
        address tokenAddress,
        address valuationOracle,
        uint256 ltv,
        uint256 liquidationThreshold
    ) external onlyOwner {
        if (tokenAddress == address(0) || valuationOracle == address(0)) {
            revert LendingPoolContractErrors.LendingPool__InvalidAddress();
        }

        s_priceFeed[tokenId] = valuationOracle;
        s_tokenAddresses[tokenId] = tokenAddress;
        s_tokenId[tokenAddress] = tokenId;
        s_tokenAddressesList.push(tokenAddress);
        s_riskParams[tokenId] = RiskParams({
            ltv: ltv,
            liquidationThreshold: liquidationThreshold,
            assetType: AssetType.RWA,
            configured: true
        });

        emit RwaAssetAdded(tokenId, tokenAddress, valuationOracle, ltv, liquidationThreshold);
    }

    /**
     * @notice Posts a real-world asset as collateral without transferring it.
     *
     * @dev The borrower keeps the tokens. A charge is recorded against their
     *      balance instead, mirroring the recorded pledge of dematerialised
     *      securities under the Depositories Act 1996 s.12 — the security stays
     *      in the pledgor's own account and the register does the work.
     *
     *      Hub-only by construction. The instrument exists on this chain and
     *      nowhere else, which is precisely why it never needs bridging: only
     *      the fact of the charge travels, as a message. Borrowing against it
     *      on a satellite needs no change, because the satellite already reads
     *      mirrored collateral.
     */
    function depositRwaCollateral(
        uint64 tokenId,
        uint256 amount
    )
        external
        payable
        isGreaterThanZero(amount)
        isTokenApprovedByTheContract(tokenId)
        nonReentrant
    {
        if (s_riskParams[tokenId].assetType != AssetType.RWA) {
            revert LendingPoolContractErrors.LendingPool__NotAnRwaAsset(tokenId);
        }
        if (block.chainid != ethChainId) {
            revert LendingPoolContractErrors.LendingPool__RwaCollateralIsHubOnly(block.chainid);
        }

        collateralController.depositRwaCollateral{value: msg.value}(
            s_tokenAddresses[tokenId],
            tokenId,
            msg.sender,
            amount
        );
    }

    /**
     * @notice Loan-to-value for an asset.
     * @dev Falls back to the protocol-wide constant for anything without
     *      configured parameters, so every asset deployed before this existed
     *      behaves exactly as it did.
     */
    function getLtv(uint64 tokenId) public view returns (uint256) {
        RiskParams memory params = s_riskParams[tokenId];
        return params.configured ? params.ltv : LTV;
    }

    function getLiquidationThreshold(uint64 tokenId) public view returns (uint256) {
        RiskParams memory params = s_riskParams[tokenId];
        return params.configured ? params.liquidationThreshold : LIQUIDATION_THRESHOLD;
    }

    /**
     * @notice When the collateral instrument redeems itself, or 0 if it never does.
     * @dev A bill reaches maturity on a fixed date and converts to cash. If that
     *      happens while it is still pledged, the lender's security evaporates —
     *      so the borrow path refuses a loan that would outlive its collateral.
     *      Tri-party repo has always worked this way; the constraint is real
     *      practice rather than a workaround.
     */
    function getAssetMaturity(uint64 tokenId) public view returns (uint64) {
        RiskParams memory params = s_riskParams[tokenId];
        if (!params.configured || params.assetType != AssetType.RWA) return 0;
        return IRWAValuation(s_priceFeed[tokenId]).maturityDate();
    }

    function getRiskParams(uint64 tokenId) external view returns (RiskParams memory) {
        return s_riskParams[tokenId];
    }

    function isRwaAsset(uint64 tokenId) external view returns (bool) {
        return s_riskParams[tokenId].assetType == AssetType.RWA && s_riskParams[tokenId].configured;
    }

    function setLienRegistry(address lienRegistry) external onlyOwner {
        s_lienRegistry = lienRegistry;
        collateralController.setLienRegistry(lienRegistry);
    }

    function getLienRegistry() external view returns (address) {
        return s_lienRegistry;
    }

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
    function burn(uint256 amount) external isGreaterThanZero(amount) {
        uint256 balance = ILpToken(lpToken).balanceOf(msg.sender);
        if (balance < amount) {
            revert LendingPoolContractErrors
                .LendingPoolContract__InsufficentLpTokenBalance();
        }
        _burnLpTokens(msg.sender, amount);
        emit LpTokensBurned(msg.sender, amount);
    }
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
    function _burnLpTokens(address user, uint256 amount) internal {
        ILpToken(lpToken).burn(user, amount);
    }
    function getLpTokenAddress() public view returns (address) {
        return address(lpToken);
    }
    function getTotalLiquidityPerToken(
        uint64 tokenId
    ) public view returns (uint256) {
        return
            block.chainid == ethChainId
                ? GSM.getTotalLiquidityPerToken(tokenId)
                : stateAggregator.readTotalLiquidityPerToken(tokenId);
    }
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
    function getValueOfLpToken() public view returns (uint256 valueOflpToken) {
        uint256 lpTokenSupply = ILpToken(lpToken).totalSupply();
        if (lpTokenSupply == 0) {
            return 0;
        }
        valueOflpToken = getTotalLiquidity() / lpTokenSupply;
    }


    function getTotalLiquidity() public view returns (uint256) {
        uint256 totalLiquidity = 0;
        for (uint256 i = 0; i < s_tokenAddressesList.length; i++) {
            uint64 tokenId = s_tokenId[s_tokenAddressesList[i]];
            totalLiquidity += getUsdValue(
                tokenId,
                getTotalLiquidityPerToken(tokenId)
            );
        }
        return totalLiquidity;
    }
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
    function getCollateralPerToken(
        uint64 tokenId
    ) external view returns (uint256) {
        // Aggregate collateral only lives on the hub chain; satellite chains keep
        // per-user mirrors, so they fall back to the locally tracked total.
        return
            block.chainid == ethChainId
                ? GSM.getTotalCollateralPerToken(tokenId)
                : s_tokenCollateral[tokenId];
    }
    function getTotalBorroweedForAToken(
        uint64 tokenId
    ) external view returns (uint256) {
        return
            block.chainid == ethChainId
                ? GSM.getTotalBorrowedPerToken(tokenId)
                : s_amountBorrowedInToken[tokenId];
    }
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
    function getUserLoanCount(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256) {
        return
            block.chainid == ethChainId
                ? GSM.readNumberOfLoanTakenPerToken(chainId, user, tokenId)
                : stateAggregator.readNumberOfLoanTakenPerToken(
                    chainId,
                    user,
                    tokenId
                );
    }
    /**
     * @notice How an asset is held when posted as collateral.
     * @dev CRYPTO transfers into the Vault. RWA does not move at all — a charge
     *      is recorded against the holder's balance instead. The distinction
     *      exists because a pool that holds a regulated instrument becomes its
     *      holder of record, which is the outcome the whole design avoids.
     */
    enum AssetType {
        CRYPTO,
        RWA
    }

    event RwaAssetAdded(
        uint64 indexed tokenId,
        address indexed tokenAddress,
        address indexed valuationOracle,
        uint256 ltv,
        uint256 liquidationThreshold
    );

    /**
     * @notice Per-asset risk, replacing the single protocol-wide LTV.
     * @dev A 91-day government bill and a volatile crypto asset cannot share a
     *      loan-to-value ratio. This is what makes 95% against a T-bill and 75%
     *      against WETH expressible at the same time.
     */
    struct RiskParams {
        uint256 ltv;
        uint256 liquidationThreshold;
        AssetType assetType;
        bool configured;
    }

    enum ActionType {
        TRANSFER,
        DEPOSIT_LIQUIDITY,
        WITHDRAW_LIQUIDITY,
        DEPOSIT_COLLATERAL,
        WITHDRAW_COLLATERAL,
        LOAN_TAKEN,
        LOAN_REPAYMENT,
        LIEN_CREATED,
        LIEN_RELEASED
    }
    struct CrossChainPayLoad {
        ActionType actionType;
        uint256 chainId;
        address user;
        uint64 crossChaintokenId;
        uint256 amountToTransfer;
        string messageToTransfer;
        bytes extraInformation;
    }
    struct CrossChainResponsePayLoad {
        Response response;
        address user;
        uint256 chainId;
        uint64 crossChainTokenId;
        uint256 amount;
        uint256 timeOfResponse;
        string messageToTransfer;
        bytes extraInformation;
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
    /**
     * @notice Overrides the hub / satellite chain ids.
     *
     * Every cross-chain branch in the protocol keys off `block.chainid ==
     * ethChainId`, so this decides which side of the protocol this deployment
     * behaves as. Defaults are set in `initialize`; only a local deployment
     * needs to change them.
     */
    /**
     * @notice Points the pool at its GlobalStateManager.
     *
     * `initialize` only wires the GSM when the deployment sits on the default
     * hub chain id. A hub running on a different id (a local node avoiding
     * MetaMask's reserved Sepolia id) sets it here instead.
     */
    function setGlobalStateManager(address gsm) external onlyOwner {
        GSM = IGlobalStateManager(gsm);
    }

    function setChainIds(uint256 ethChainId_, uint256 arbChainId_) external onlyOwner {
        ethChainId = ethChainId_;
        arbChainId = arbChainId_;
    }

    function getStableCoinAddress() external view returns (address) {
        return i_stableCoinAddress;
    }

    // The controllers are where every protocol event is actually emitted, and
    // the GSM is where liquidations are. An off-chain indexer needs their
    // addresses to know which logs to watch, and discovering them from the pool
    // keeps it working against any deployment without extra configuration.

    function getLiquidityControllerAddress() external view returns (address) {
        return address(liquidityController);
    }

    function getCollateralControllerAddress() external view returns (address) {
        return address(collateralController);
    }

    function getLoanControllerAddress() external view returns (address) {
        return address(loanController);
    }

    function getGSMAddress() external view returns (address) {
        return address(GSM);
    }
    receive() external payable {}
}
