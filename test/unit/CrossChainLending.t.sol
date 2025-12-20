// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {BurnMintERC677Helper, BurnMintERC677} from "@chainlink/local/src/ccip/BurnMintERC677Helper.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {LendingPoolContract} from "../../src/LendingPoolContract.sol";
import {InterestRateModel} from "../../src/InterestRate/InterestRateModel.sol";
import {StableCoin} from "../../src/tokens/StableCoin.sol";
import {GlobalStateManager} from "../../src/GSM/GlobalStateManager.sol";
import {LpToken} from "../../src/tokens/LpTokenContract.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Registry} from "../../src/AdminRegistry/Registry.sol";
import {LoanManager} from "../../src/GSM/LoanManager.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Vault} from "../../src/Vault.sol";
import {CrossChainMessageSender} from "../../src/ccip/CrossChainMessageSender.sol";
import {CrossChainMessageReceiver} from "../../src/ccip/CrossChainMessageReceiver.sol";
import {CCIPReceiver} from "../../src/ccip/CCIPReceiver.sol";
import {CCIPRequestHandler} from "../../src/ccip/CCIPRequestHandler.sol";
import {CrossChainMessageReceiver} from "../../src/ccip/CrossChainMessageReceiver.sol";
import {LiquidityController} from "../../src/service/LiquidityController.sol";
import {CollateralController} from "../../src/service/CollateralController.sol";
import {LoanController} from "../../src/service/LoanController.sol";
import {StateAggregator} from "../../src/StateMirror/StateAggregator.sol";

contract CrossChainLending is Test {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    BurnMintERC677Helper public wethSepolia;
    BurnMintERC677Helper public wethArbSepolia;
    Register.NetworkDetails sepoliaNetworkDetails;
    GlobalStateManager GSM;
    Registry registrySepolia;
    address crossChainMessageReceiverAddressArbSepolia;

    Register.NetworkDetails arbSepoliaNetworkDetails;
    uint256 sepoliaFork;

    uint256 arbSepoliaFork;

    MockV3Aggregator wethUsdPriceFeedAddressSepolia;
    MockV3Aggregator wethUsdPriceFeedAddressArbSepolia;

    StableCoin stableCoinSepolia;
    StableCoin stableCoinArbSepolia;

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 1000e8;

    address ownerSepolia = makeAddr("ownerSepolia");
    address ownerArbSepolia = makeAddr("ownerArbSepolia");
    address user = makeAddr("user");
    address loanUser = makeAddr("loanUser");

    LendingPoolContract lendingPoolContractSepolia;
    LendingPoolContract lendingPoolContractArbSepolia;
    address[] public tokenAddressSepolia;
    address[] public tokenAddressArbSepolia;
    address[] public priceFeedAddressSepolia;
    address[] public priceFeedAddressArbSepolia;
    address vaultSepoliaAddress;
    address vaultArbSepoliaAddress;

    address arbCrossChainReceiverAddress;

    uint64[] public chainIdSepolia;
    uint64[] public chainIdArbSepolia;

    function setUp() public {
        sepoliaFork = vm.createSelectFork("eth");
        arbSepoliaFork = vm.createFork("arb");
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(
            block.chainid
        );
        wethSepolia = BurnMintERC677Helper(
            sepoliaNetworkDetails.ccipBnMAddress
        );
        wethUsdPriceFeedAddressSepolia = new MockV3Aggregator(
            DECIMALS,
            ETH_USD_PRICE
        );
        vm.startPrank(ownerSepolia);

        console.log("address of owner in sepolia is ", ownerArbSepolia);
        tokenAddressSepolia = [address(wethSepolia)];
        chainIdSepolia = [uint64(11155111), uint64(421614)];
        priceFeedAddressSepolia = [address(wethUsdPriceFeedAddressSepolia)];
        lendingPoolContractSepolia = new LendingPoolContract();
        InterestRateModel interestRateModelSepolia = new InterestRateModel();

        stableCoinSepolia = new StableCoin();
        LpToken lpTokenSepolia = new LpToken();
        registrySepolia = new Registry();
        GSM = new GlobalStateManager(
            address(registrySepolia),
            address(interestRateModelSepolia)
        );
        registrySepolia.setDestinationChainSelector(
            11155111,
            16015286601757825753
        );
        registrySepolia.setDestinationChainSelector(
            421614,
            3478487238524512106
        );

        Vault vaultSepolia = new Vault(
            address(lendingPoolContractSepolia),
            address(stableCoinSepolia)
        );

        CrossChainMessageSender crossChainMessageSenderSepolia = new CrossChainMessageSender(
                sepoliaNetworkDetails.linkAddress,
                sepoliaNetworkDetails.routerAddress
            );
        CCIPRequestHandler ccipRequestHandlerSepolia = new CCIPRequestHandler(
            address(lendingPoolContractSepolia),
            address(registrySepolia),
            address(GSM),
            address(crossChainMessageSenderSepolia)
        );
        CCIPReceiver ccipReceiverSepolia = new CCIPReceiver(
            address(lendingPoolContractSepolia),
            address(registrySepolia),
            address(ccipRequestHandlerSepolia),
            address(stableCoinSepolia)
        );
        CrossChainMessageReceiver crossChainMessageReceiverSepolia = new CrossChainMessageReceiver(
                sepoliaNetworkDetails.routerAddress,
                address(ccipReceiverSepolia)
            );
        LiquidityController liquidityControllerSepolia = new LiquidityController(
                address(registrySepolia),
                address(lendingPoolContractSepolia),
                address(vaultSepolia),
                address(GSM),
                address(GSM),
                address(lpTokenSepolia)
            );

        CollateralController collateralControllerSepolia = new CollateralController(
                address(registrySepolia),
                address(vaultSepolia),
                address(GSM),
                address(lendingPoolContractSepolia),
                address(GSM)
            );
        console.log(
            "address of collateralController",
            address(collateralControllerSepolia)
        );

        LoanController loanControllerSepolia = new LoanController(
            address(GSM),
            address(GSM),
            address(lendingPoolContractSepolia),
            address(registrySepolia),
            address(vaultSepolia)
        );

        crossChainMessageSenderSepolia.setAllowedCallers(
            address(liquidityControllerSepolia),
            true
        );
        crossChainMessageSenderSepolia.setAllowedCallers(
            address(collateralControllerSepolia),
            true
        );
        crossChainMessageSenderSepolia.setAllowedCallers(
            address(loanControllerSepolia),
            true
        );

        address[] memory authorizedAddressesSepolia = new address[](3);
        authorizedAddressesSepolia[0] = address(liquidityControllerSepolia);
        authorizedAddressesSepolia[1] = address(collateralControllerSepolia);
        authorizedAddressesSepolia[2] = address(loanControllerSepolia);

        vaultSepolia.setAuthorizedContracts(authorizedAddressesSepolia, true);
        for (uint256 i = 0; i < authorizedAddressesSepolia.length; i++) {
            GSM.setAllowedChains(authorizedAddressesSepolia[i]);
        }
        lendingPoolContractSepolia.initialize(
            tokenAddressSepolia,
            priceFeedAddressSepolia,
            chainIdSepolia,
            address(stableCoinSepolia),
            address(lpTokenSepolia),
            sepoliaNetworkDetails.linkAddress,
            address(GSM),
            address(registrySepolia),
            address(vaultSepolia),
            address(crossChainMessageSenderSepolia),
            address(ccipReceiverSepolia),
            address(ccipRequestHandlerSepolia),
            address(GSM),
            address(crossChainMessageReceiverSepolia),
            address(liquidityControllerSepolia),
            address(collateralControllerSepolia),
            address(loanControllerSepolia)
        );

        ERC20Mock(address(stableCoinSepolia)).mint(
            lendingPoolContractSepolia.getVaultAddress(),
            100000 ether
        );
        ERC20Mock(address(stableCoinSepolia)).mint(user, 100000 ether);
        ERC20Mock(address(stableCoinSepolia)).mint(loanUser, 100000 ether);

        GSM.setCrosssChainMessageSenderAddress(
            lendingPoolContractSepolia.getCrossChainMessageSenderAddress()
        );

        GSM.setAllowedChains(address(lendingPoolContractSepolia));
        GSM.setAllowedChains(
            address(lendingPoolContractSepolia.getCCIPRequestHanlderAddress())
        );
        interestRateModelSepolia.setLendingPoolContractAndGSM(
            address(lendingPoolContractSepolia),
            address(GSM)
        );
        interestRateModelSepolia.transferOwnership(
            address(lendingPoolContractSepolia)
        );
        stableCoinSepolia.transferOwnership(
            address(lendingPoolContractSepolia)
        );
        lpTokenSepolia.transferOwnership(address(liquidityControllerSepolia));

        crossChainMessageSenderSepolia.transferOwnership(
            address(lendingPoolContractSepolia)
        );

        ccipRequestHandlerSepolia.transferOwnership(
            address(lendingPoolContractSepolia)
        );
        ccipReceiverSepolia.transferOwnership(
            address(lendingPoolContractSepolia)
        );
        crossChainMessageReceiverSepolia.transferOwnership(
            address(lendingPoolContractSepolia)
        );

        liquidityControllerSepolia.transferOwnership(
            address(lendingPoolContractSepolia)
        );

        collateralControllerSepolia.transferOwnership(
            address(lendingPoolContractSepolia)
        );

        loanControllerSepolia.transferOwnership(
            address(lendingPoolContractSepolia)
        );

        lendingPoolContractSepolia.setGSMAddress(address(GSM));

        address crossChainMessageSenderAddressSepolia = lendingPoolContractSepolia
                .getCrossChainMessageSenderAddress();
        address ccipRequestHandlerAddress = lendingPoolContractSepolia
            .getCCIPRequestHanlderAddress();

        registrySepolia.setAddress(
            11155111,
            "crossChainMessageSenderAddress",
            crossChainMessageSenderAddressSepolia
        );

        registrySepolia.setAddress(
            11155111,
            "crossChainMessageSenderAddress",
            address(crossChainMessageSenderSepolia)
        );

        registrySepolia.setAddress(
            11155111,
            "ccipRequestHandlerAddress",
            ccipRequestHandlerAddress
        );
        lendingPoolContractSepolia.setAllowedCallersFoCrossChainMessageSender(
            ccipRequestHandlerAddress,
            true
        );
        lendingPoolContractSepolia.setAllowedCallersFoCrossChainMessageSender(
            address(GSM),
            true
        );

        vm.stopPrank();

        wethSepolia.drip(user);
        wethSepolia.drip(user);
        wethSepolia.drip(user);
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, 5 ether);
        wethSepolia.drip(loanUser);
        wethSepolia.drip(loanUser);
        wethSepolia.drip(loanUser);
        ccipLocalSimulatorFork.requestLinkFromFaucet(loanUser, 5 ether);

        address senderCCIPAddress = lendingPoolContractSepolia
            .getCrossChainMessageSenderAddress();

        vaultSepoliaAddress = lendingPoolContractSepolia.getVaultAddress();

        address crossChainMessageReceiverAddressSepolia = lendingPoolContractSepolia
                .getCrossChainMessageReceiverAddress();

        vm.deal(
            lendingPoolContractSepolia.getCrossChainMessageSenderAddress(),
            100 ether
        );
        vm.deal(user, 1 ether);
        vm.deal(loanUser, 1 ether);

        vm.selectFork(arbSepoliaFork);

        wethUsdPriceFeedAddressArbSepolia = new MockV3Aggregator(
            DECIMALS,
            ETH_USD_PRICE
        );
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(
            block.chainid
        );
        wethArbSepolia = BurnMintERC677Helper(
            arbSepoliaNetworkDetails.ccipBnMAddress
        );

        vm.startPrank(ownerArbSepolia);

        tokenAddressArbSepolia = [address(wethArbSepolia)];
        priceFeedAddressArbSepolia = [
            address(wethUsdPriceFeedAddressArbSepolia)
        ];
        chainIdArbSepolia = [uint64(11155111), uint64(421614)];
        stableCoinArbSepolia = new StableCoin();
        LpToken lpTokenArbSepolia = new LpToken();
        Registry arbSepoliaRegistry = new Registry();

        arbSepoliaRegistry.setDestinationChainSelector(
            11155111,
            16015286601757825753
        );
        arbSepoliaRegistry.setDestinationChainSelector(
            421614,
            3478487238524512106
        );
        lendingPoolContractArbSepolia = new LendingPoolContract();
        Vault vaultArbSepolia = new Vault(
            address(lendingPoolContractArbSepolia),
            address(stableCoinArbSepolia)
        );

        CrossChainMessageSender crossChainMessageSenderArbSepolia = new CrossChainMessageSender(
                arbSepoliaNetworkDetails.linkAddress,
                arbSepoliaNetworkDetails.routerAddress
            );

        StateAggregator stateAggregator = new StateAggregator();

        CCIPReceiver ccipReceiverArbSepolia = new CCIPReceiver(
            address(lendingPoolContractArbSepolia),
            address(arbSepoliaRegistry),
            address(stableCoinArbSepolia),
            address(stateAggregator)
        );
        CrossChainMessageReceiver crossChainMessageReceiverArbSepolia = new CrossChainMessageReceiver(
                arbSepoliaNetworkDetails.routerAddress,
                address(ccipReceiverArbSepolia)
            );
        LiquidityController liquidityControllerArbSepolia = new LiquidityController(
                address(arbSepoliaRegistry),
                address(lendingPoolContractArbSepolia),
                address(vaultArbSepolia),
                address(stateAggregator),
                address(stateAggregator),
                address(lpTokenArbSepolia)
            );

        CollateralController collateralControllerArbSepolia = new CollateralController(
                address(arbSepoliaRegistry),
                address(vaultArbSepolia),
                address(stateAggregator),
                address(lendingPoolContractArbSepolia),
                address(stateAggregator)
            );

        LoanController loanControllerArbSepolia = new LoanController(
            address(stateAggregator),
            address(stateAggregator),
            address(lendingPoolContractArbSepolia),
            address(arbSepoliaRegistry),
            address(vaultArbSepolia)
        );

        crossChainMessageSenderArbSepolia.setAllowedCallers(
            address(liquidityControllerArbSepolia),
            true
        );

        crossChainMessageSenderArbSepolia.setAllowedCallers(
            address(collateralControllerArbSepolia),
            true
        );
        crossChainMessageSenderArbSepolia.setAllowedCallers(
            address(loanControllerArbSepolia),
            true
        );
        address[] memory authorizedAddressesArbSepolia = new address[](3);
        authorizedAddressesArbSepolia[0] = address(
            liquidityControllerArbSepolia
        );
        authorizedAddressesArbSepolia[1] = address(
            collateralControllerArbSepolia
        );
        authorizedAddressesArbSepolia[2] = address(loanControllerArbSepolia);
        vaultArbSepolia.setAuthorizedContracts(
            authorizedAddressesArbSepolia,
            true
        );

        stateAggregator.setAuthorizedUpdators(address(ccipReceiverArbSepolia),true);
        stateAggregator.setAuthorizedReadors(
            address(collateralControllerArbSepolia),
            true
        );
        stateAggregator.setAuthorizedReadors(
            address(liquidityControllerArbSepolia),
            true
        );
        stateAggregator.setAuthorizedReadors(
            address(loanControllerArbSepolia),
            true
        );

        stateAggregator.setAuthorizedReadors(address(lendingPoolContractArbSepolia),true);

        stateAggregator.transferOwnership(
            address(lendingPoolContractArbSepolia)
        );
        lendingPoolContractArbSepolia.initialize(
            tokenAddressArbSepolia,
            priceFeedAddressArbSepolia,
            chainIdArbSepolia,
            address(stableCoinArbSepolia),
            address(lpTokenArbSepolia),
            arbSepoliaNetworkDetails.linkAddress,
            address(stateAggregator),
            address(arbSepoliaRegistry),
            address(vaultArbSepolia),
            address(crossChainMessageSenderArbSepolia),
            address(ccipReceiverArbSepolia),
            address(ccipReceiverArbSepolia),
            address(stateAggregator),
            address(crossChainMessageReceiverArbSepolia),
            address(liquidityControllerArbSepolia),
            address(collateralControllerArbSepolia),
            address(loanControllerArbSepolia)
        );
        ERC20Mock(address(stableCoinArbSepolia)).mint(
            lendingPoolContractArbSepolia.getVaultAddress(),
            10000 ether
        );
        ERC20Mock(address(stableCoinArbSepolia)).mint(user, 10000 ether);
        ERC20Mock(address(stableCoinArbSepolia)).mint(loanUser, 10000 ether);

        stableCoinArbSepolia.transferOwnership(
            address(lendingPoolContractArbSepolia)
        );
        lpTokenArbSepolia.transferOwnership(
            address(liquidityControllerArbSepolia)
        );

        crossChainMessageSenderArbSepolia.transferOwnership(
            address(lendingPoolContractArbSepolia)
        );

        ccipReceiverArbSepolia.transferOwnership(
            address(lendingPoolContractArbSepolia)
        );
        crossChainMessageReceiverArbSepolia.transferOwnership(
            address(lendingPoolContractArbSepolia)
        );

        liquidityControllerArbSepolia.transferOwnership(
            address(lendingPoolContractArbSepolia)
        );

        collateralControllerArbSepolia.transferOwnership(
            address(lendingPoolContractArbSepolia)
        );

        loanControllerArbSepolia.transferOwnership(
            address(lendingPoolContractArbSepolia)
        );
        lendingPoolContractArbSepolia.setallowListedSenders(senderCCIPAddress);
        lendingPoolContractArbSepolia.setallowListedSenders(
            address(liquidityControllerSepolia)
        );
        lendingPoolContractArbSepolia.setallowListedSenders(
            address(loanControllerSepolia)
        );
        lendingPoolContractArbSepolia.setallowListedSenders(
            address(collateralControllerSepolia)
        );

        arbCrossChainReceiverAddress = lendingPoolContractArbSepolia
            .getCrossChainMessageReceiverAddress();
        vaultArbSepoliaAddress = lendingPoolContractArbSepolia.getVaultAddress();
        vm.deal(
            lendingPoolContractArbSepolia.getCrossChainMessageSenderAddress(),
            100 ether
        );
        arbSepoliaRegistry.setCrossChainRegistryAddress(
            arbSepoliaRegistry.getDestinationChainSelector(11155111),
            "crossChainMessageReceiverAddress",
            crossChainMessageReceiverAddressSepolia
        );

        arbSepoliaRegistry.setAddress(
            421614,
            "crossChainMessageSenderAddress",
            address(crossChainMessageSenderArbSepolia)
        );

        address crossChainMessageSenderAddressArbSepolia = lendingPoolContractArbSepolia
                .getCrossChainMessageSenderAddress();

        crossChainMessageReceiverAddressArbSepolia = lendingPoolContractArbSepolia
            .getCrossChainMessageReceiverAddress();
        lendingPoolContractArbSepolia.setAllowListedSenders(
            crossChainMessageSenderAddressSepolia,
            true
        );

        vm.stopPrank();

        wethArbSepolia.drip(user);
        wethArbSepolia.drip(user);
        wethArbSepolia.drip(user);

        vm.deal(user, 1 ether);
        wethArbSepolia.drip(loanUser);
        wethArbSepolia.drip(loanUser);
        wethArbSepolia.drip(loanUser);

        vm.deal(loanUser, 1 ether);

        vm.selectFork(sepoliaFork);

        vm.startPrank(ownerSepolia);
        lendingPoolContractSepolia.setAllowListedSenders(
            crossChainMessageSenderAddressArbSepolia,
            true
        );

        registrySepolia.setCrossChainRegistryAddress(
            registrySepolia.getDestinationChainSelector(421614),
            "crossChainMessageReceiverAddress",
            crossChainMessageReceiverAddressArbSepolia
        );

        vm.stopPrank();

        vm.selectFork(arbSepoliaFork);
    }

    function testCollateralDepositAndStateUpdateInGSMFromSameChain() public {
        vm.selectFork(sepoliaFork);

        vm.startPrank(user);
        BurnMintERC677(wethSepolia).approve(vaultSepoliaAddress, 1 ether);
        lendingPoolContractSepolia.depositCollateral(0, 1 ether);

        vm.deal(
            lendingPoolContractSepolia.getCrossChainMessageSenderAddress(),
            100 ether
        );

        vm.stopPrank();

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        vm.selectFork(arbSepoliaFork);

        uint256 details = lendingPoolContractArbSepolia
            .getCollateralDetailsOfUser(11155111, user, 0);
        assertEq(details, 1 ether);
    }

    function testCollateralDespoistANdStateUpdateFromOtherChainAndCheckInMainChain()
        public
    {
        vm.selectFork(arbSepoliaFork);

        vm.startPrank(user);

        BurnMintERC677(wethArbSepolia).approve(vaultArbSepoliaAddress, 1 ether);
        lendingPoolContractArbSepolia.depositCollateral{value: 0.5 ether}(
            0,
            1 ether
        );
        vm.deal(
            lendingPoolContractArbSepolia.getCrossChainMessageSenderAddress(),
            100 ether
        );

        vm.stopPrank();

        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork);

        uint256 details = lendingPoolContractSepolia.getCollateralDetailsOfUser(
            421614,
            user,
            0
        );
        assertEq(details, 1 ether);
    }

    function testCollateralDepositAndBalanceCheckInSubChain() public {
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(user);

        BurnMintERC677(wethArbSepolia).approve(vaultArbSepoliaAddress, 1 ether);
        lendingPoolContractArbSepolia.depositCollateral{value: 0.5 ether}(
            0,
            1 ether
        );

        vm.deal(
            lendingPoolContractArbSepolia.getCrossChainMessageSenderAddress(),
            100 ether
        );

        vm.stopPrank();

        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork);

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        uint256 details = lendingPoolContractArbSepolia
            .getCollateralDetailsOfUser(421614, user, 0);
        assertEq(details, 1 ether);
    }

    function testDepositAndLpTokens() public {
        vm.selectFork(sepoliaFork);
        vm.startPrank(user);

        BurnMintERC677(wethSepolia).approve(vaultSepoliaAddress, 1 ether);
        lendingPoolContractSepolia.depositLiquidity{value: 0.3 ether}(
            0,
            1 ether
        );
        vm.deal(
            lendingPoolContractSepolia.getCrossChainMessageSenderAddress(),
            100 ether
        );

        vm.stopPrank();

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        uint256 deposit = lendingPoolContractArbSepolia.getUserBalance(
            11155111,
            user,
            0
        );

        uint256 lptokenAmount = lendingPoolContractArbSepolia
            .getTotalLPTokensForTheUser(user);
        assertEq(lptokenAmount, 1 ether);
        assertEq(deposit, 1 ether);
    }

    // depositing the collatearl on ethereum and take loan on arb and repay it back on ethereum

    // 3 users

    // 1. user1 deposits liquidity into the protocol
    // 2. user2 depsoits collatearl into the protocol through eth and takes loan from arb
    // 3. user3 deposits collateral into the protocol through arb and takes loan from eth and then the user4 repays the laon amount back through the eth chain and the invarients adn the test should hold

    function testOnMainChainAndReflectOnSubChain() public {
        vm.selectFork(sepoliaFork);

        vm.prank(ownerSepolia);
        GSM.setParamsCrossChain(
            crossChainMessageReceiverAddressArbSepolia,
            421614,
            registrySepolia.getDestinationChainSelector(421614)
        );

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        vm.selectFork(sepoliaFork);
        vm.startPrank(user);
        BurnMintERC677(wethSepolia).approve(vaultSepoliaAddress, 1 ether);
        lendingPoolContractSepolia.depositLiquidity(0, 1 ether);

        vm.deal(
            lendingPoolContractSepolia.getCrossChainMessageSenderAddress(),
            100 ether
        );

        vm.stopPrank();
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);
        vm.selectFork(sepoliaFork);

        vm.startPrank(loanUser);
        BurnMintERC677(wethSepolia).approve(vaultSepoliaAddress, 1 ether);
        lendingPoolContractSepolia.depositCollateral{value: 0.3 ether}(
            0,
            1 ether
        );

        vm.deal(
            lendingPoolContractSepolia.getCrossChainMessageSenderAddress(),
            100 ether
        );

        vm.stopPrank();

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        vm.selectFork(sepoliaFork);

        vm.startPrank(loanUser);

        uint256 collateralAvailableForBorrowingInUsd2 = lendingPoolContractSepolia
                .getUsdValue(0, 0.7 ether);
        lendingPoolContractSepolia.borrowLoan{value: 0.4 ether}(
            11155111,
            0,
            collateralAvailableForBorrowingInUsd2
        );

        vm.stopPrank();

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);
        vm.warp(block.timestamp + 30 days);

        vm.selectFork(sepoliaFork);

        vm.startPrank(loanUser);

        uint256 amountToRepay = lendingPoolContractSepolia.getAmountToRepay(
            11155111,
            0,
            1
        );

        IERC20(stableCoinSepolia).approve(vaultSepoliaAddress, amountToRepay);

        lendingPoolContractSepolia.repayLoan{value: 0.2 ether}(
            11155111,
            0,
            amountToRepay,
            1
        );

        vm.stopPrank();

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        assertEq(
            lendingPoolContractArbSepolia
                .getLoanDetails(11155111, loanUser, 0, 1)
                .amountBorrowedInUSDT,
            0
        );
    }

    function testtakeAndRepayLoanOnTheSubChain() public {
        vm.selectFork(sepoliaFork);

        vm.deal(
            lendingPoolContractSepolia.getCrossChainMessageSenderAddress(),
            100 ether
        );

        vm.prank(ownerSepolia);
        GSM.setParamsCrossChain(
            crossChainMessageReceiverAddressArbSepolia,
            421614,
            registrySepolia.getDestinationChainSelector(421614)
        );

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        vm.selectFork(arbSepoliaFork);
        vm.startPrank(user);
        BurnMintERC677(wethArbSepolia).approve(vaultArbSepoliaAddress, 1 ether);
        lendingPoolContractArbSepolia.depositLiquidity{value: 0.2 ether}(
            0,
            1 ether
        );

        vm.deal(
            lendingPoolContractArbSepolia.getCrossChainMessageSenderAddress(),
            100 ether
        );

        vm.stopPrank();
        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        uint256 userBalance1 = lendingPoolContractArbSepolia.getUserBalance(
            421614,
            user,
            0
        );
        assertEq(userBalance1, 1 ether);

        vm.selectFork(sepoliaFork);

        uint256 userBalance = lendingPoolContractSepolia.getUserBalance(
            421614,
            user,
            0
        );

        assertEq(userBalance, 1 ether);

        vm.selectFork(arbSepoliaFork);

        vm.startPrank(loanUser);
        BurnMintERC677(wethArbSepolia).approve(vaultArbSepoliaAddress, 1 ether);
        lendingPoolContractArbSepolia.depositCollateral{value: 0.3 ether}(
            0,
            1 ether
        );

        vm.stopPrank();

        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        vm.selectFork(sepoliaFork);

        uint256 collateralAmount1 = lendingPoolContractSepolia
            .getCollateralDetailsOfUser(421614, loanUser, 0);
        assertEq(collateralAmount1, 1 ether);
        vm.selectFork(arbSepoliaFork);

        uint256 collateralAmount2 = lendingPoolContractArbSepolia
            .getCollateralDetailsOfUser(421614, loanUser, 0);

        assertEq(collateralAmount2, 1 ether);

        vm.startPrank(loanUser);

        uint256 collateralAvailableForBorrowingInUsd2 = lendingPoolContractArbSepolia
                .getUsdValue(0, 0.7 ether);
        lendingPoolContractArbSepolia.borrowLoan{value: 0.4 ether}(
            421614,
            0,
            collateralAvailableForBorrowingInUsd2
        );

        vm.stopPrank();

        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        vm.selectFork(sepoliaFork);

        LoanManager.LoanDetails memory loanDetails = lendingPoolContractSepolia
            .getLoanDetails(421614, loanUser, 0, 1);

        assertEq(
            loanDetails.amountBorrowedInUSDT,
            collateralAvailableForBorrowingInUsd2
        );

        vm.selectFork(arbSepoliaFork);

        LoanManager.LoanDetails
            memory loanDetails2 = lendingPoolContractArbSepolia.getLoanDetails(
                421614,
                loanUser,
                0,
                1
            );

        assertEq(
            loanDetails2.amountBorrowedInUSDT,
            collateralAvailableForBorrowingInUsd2
        );

        vm.warp(block.timestamp + 30 days);

        vm.selectFork(sepoliaFork);

        vm.startPrank(loanUser);

        uint256 amountToRepay = lendingPoolContractSepolia.getAmountToRepay(
            421614,
            0,
            1
        );

        IERC20(stableCoinSepolia).approve(vaultSepoliaAddress, amountToRepay);

        lendingPoolContractSepolia.repayLoan{value: 0.2 ether}(
            421614,
            0,
            amountToRepay,
            1
        );

        vm.stopPrank();

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        vm.selectFork(arbSepoliaFork);

        assertEq(
            lendingPoolContractArbSepolia
                .getLoanDetails(421614, loanUser, 0, 1)
                .amountBorrowedInUSDT,
            0
        );
    }

    function testTakeLoanInOneChainAndRepayInOtherChain() public {
        // user deposits collateral in arbSepolia
        // user takes loan in sepolia
        // user repays the loan in arbSepolia

        vm.selectFork(sepoliaFork);

        vm.prank(ownerSepolia);
        GSM.setParamsCrossChain(
            crossChainMessageReceiverAddressArbSepolia,
            421614,
            registrySepolia.getDestinationChainSelector(421614)
        );

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        vm.selectFork(arbSepoliaFork);

        vm.deal(
            lendingPoolContractArbSepolia.getCrossChainMessageSenderAddress(),
            100 ether
        );

        vm.startPrank(loanUser);

        BurnMintERC677(wethArbSepolia).approve(vaultArbSepoliaAddress, 1 ether);
        lendingPoolContractArbSepolia.depositCollateral{value: 0.3 ether}(
            0,
            1 ether
        );
        vm.stopPrank();

        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork);

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        vm.selectFork(sepoliaFork);

        vm.startPrank(loanUser);

        uint256 collateralAvailableForBorrowingInUsd2 = lendingPoolContractSepolia
                .getUsdValue(0, 0.7 ether);
        lendingPoolContractSepolia.borrowLoan{value: 0.4 ether}(
            421614,
            0,
            collateralAvailableForBorrowingInUsd2
        );

        vm.stopPrank();

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        vm.startPrank(loanUser);

        uint256 amountToRepay = lendingPoolContractArbSepolia.getAmountToRepay(
            11155111,
            0,
            1
        );

        IERC20(stableCoinArbSepolia).approve(
            vaultArbSepoliaAddress,
            amountToRepay
        );

        lendingPoolContractArbSepolia.repayLoan{value: 0.2 ether}(
            11155111,
            0,
            amountToRepay,
            1
        );

        vm.stopPrank();
        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        assertEq(
            lendingPoolContractArbSepolia
                .getLoanDetails(11155111, loanUser, 0, 1)
                .amountBorrowedInUSDT,
            0
        );

        vm.selectFork(sepoliaFork);

        assertEq(
            lendingPoolContractSepolia
                .getLoanDetails(11155111, loanUser, 0, 1)
                .amountBorrowedInUSDT,
            0
        );
    }

    function testTakeLoanInOneChainAndRepayInOtherChainSecondTest() public {
        // user deposits collateral in sepolia
        // user takes loan in arbsepolia
        // user repays the loan in sepolia

        vm.selectFork(sepoliaFork);

        vm.prank(ownerSepolia);
        GSM.setParamsCrossChain(
            crossChainMessageReceiverAddressArbSepolia,
            421614,
            registrySepolia.getDestinationChainSelector(421614)
        );

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        vm.deal(
            lendingPoolContractArbSepolia.getCrossChainMessageSenderAddress(),
            100 ether
        );

        vm.selectFork(sepoliaFork);

        vm.deal(
            lendingPoolContractSepolia.getCrossChainMessageSenderAddress(),
            100 ether
        );

        vm.startPrank(loanUser);

        BurnMintERC677(wethSepolia).approve(vaultSepoliaAddress, 1 ether);
        lendingPoolContractSepolia.depositCollateral{value: 0.3 ether}(
            0,
            1 ether
        );
        vm.stopPrank();

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        vm.startPrank(loanUser);

        uint256 collateralAvailableForBorrowingInUsd2 = lendingPoolContractArbSepolia
                .getUsdValue(0, 0.7 ether);
        lendingPoolContractArbSepolia.borrowLoan{value: 0.4 ether}(
            11155111,
            0,
            collateralAvailableForBorrowingInUsd2
        );

        vm.stopPrank();

        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        vm.selectFork(sepoliaFork);
        vm.startPrank(loanUser);

        uint256 amountToRepay = lendingPoolContractSepolia.getAmountToRepay(
            421614,
            0,
            1
        );

        IERC20(stableCoinSepolia).approve(vaultSepoliaAddress, amountToRepay);

        lendingPoolContractSepolia.repayLoan{value: 0.2 ether}(
            421614,
            0,
            amountToRepay,
            1
        );

        vm.stopPrank();
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        assertEq(
            lendingPoolContractArbSepolia
                .getLoanDetails(421614, loanUser, 0, 1)
                .amountBorrowedInUSDT,
            0
        );

        vm.selectFork(sepoliaFork);

        assertEq(
            lendingPoolContractSepolia
                .getLoanDetails(421614, loanUser, 0, 1)
                .amountBorrowedInUSDT,
            0
        );
    }

    // TO-DO: the repay function is put at hold and will be take care in the future due to failure of the ccip functon, now going to implement the auto liquidation

    function testLiquidation() public {
        vm.selectFork(sepoliaFork);

        vm.prank(ownerSepolia);
        GSM.setParamsCrossChain(
            crossChainMessageReceiverAddressArbSepolia,
            421614,
            registrySepolia.getDestinationChainSelector(421614)
        );

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        vm.selectFork(sepoliaFork);
        vm.startPrank(user);
        BurnMintERC677(wethSepolia).approve(vaultSepoliaAddress, 1 ether);
        lendingPoolContractSepolia.depositLiquidity(0, 1 ether);

        vm.deal(
            lendingPoolContractSepolia.getCrossChainMessageSenderAddress(),
            100 ether
        );

        vm.stopPrank();
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        vm.startPrank(user);

        BurnMintERC677(wethArbSepolia).approve(vaultArbSepoliaAddress, 1 ether);
        lendingPoolContractArbSepolia.depositCollateral{value: 0.5 ether}(
            0,
            1 ether
        );

        vm.deal(
            lendingPoolContractArbSepolia.getCrossChainMessageSenderAddress(),
            100 ether
        );

        vm.stopPrank();
        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        vm.selectFork(sepoliaFork);

        vm.startPrank(user);

        uint256 collateralAvailableForBorrowingInUsd = lendingPoolContractSepolia
                .getUsdValue(0, 0.7 ether);
        lendingPoolContractSepolia.borrowLoan{value: 0.4 ether}(
            421614,
            0,
            collateralAvailableForBorrowingInUsd
        );

        vm.stopPrank();

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        vm.selectFork(sepoliaFork);

        vm.warp(block.timestamp + 120 days);

        (bool upkeepNeeded, bytes memory performData) = GSM.checkUpkeep("");
        if (upkeepNeeded) {
            GSM.performUpkeep(performData);
        }
        vm.warp(block.timestamp + 120 days);

        (upkeepNeeded, performData) = GSM.checkUpkeep("");
        if (upkeepNeeded) {
            GSM.performUpkeep(performData);
        }
        vm.warp(block.timestamp + 120 days);

        (upkeepNeeded, performData) = GSM.checkUpkeep("");
        if (upkeepNeeded) {
            GSM.performUpkeep(performData);
        }

        LoanManager.LoanDetails memory loan = lendingPoolContractSepolia
            .getLoanDetails(421614, loanUser, 0, 1);

        assertEq(loan.amountBorrowedInUSDT, 0);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        LoanManager.LoanDetails memory loan2 = lendingPoolContractArbSepolia
            .getLoanDetails(421614, loanUser, 0, 1);

        assertEq(loan2.amountBorrowedInUSDT, 0);
    }
}
