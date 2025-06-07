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

contract CrossChainLending is Test {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    BurnMintERC677Helper public wethSepolia;
    BurnMintERC677Helper public wethArbSepolia;
    Register.NetworkDetails sepoliaNetworkDetails;

    Register.NetworkDetails arbSepoliaNetworkDetails;
    uint256 sepoliaFork;

    uint256 arbSepoliaFork;

    MockV3Aggregator wethUsdPriceFeedAddressSepolia;
    MockV3Aggregator wethUsdPriceFeedAddressArbSepolia;

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 1000e8;

    address ownerSepolia = makeAddr("ownerSepolia");
    address ownerArbSepolia = makeAddr("ownerArbSepolia");
    address user = makeAddr("user");

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
        tokenAddressSepolia = [address(wethSepolia)];
        chainIdSepolia = [uint64(11155111), uint64(421614)];
        priceFeedAddressSepolia = [address(wethUsdPriceFeedAddressSepolia)];
        InterestRateModel interestRateModelSepolia = new InterestRateModel();
        StableCoin stableCoinSepolia = new StableCoin();
        LpToken lpTokenSepolia = new LpToken();
        Registry registrySepolia = new Registry();
        GlobalStateManager GSM = new GlobalStateManager(
            address(registrySepolia)
        );
        registrySepolia.setDestinationChainSelector(
            11155111,
            16015286601757825753
        );
        registrySepolia.setDestinationChainSelector(
            421614,
            3478487238524512106
        );
        lendingPoolContractSepolia = new LendingPoolContract(
            tokenAddressSepolia,
            priceFeedAddressSepolia,
            chainIdSepolia,
            address(stableCoinSepolia),
            address(lpTokenSepolia),
            address(interestRateModelSepolia),
            sepoliaNetworkDetails.linkAddress,
            sepoliaNetworkDetails.routerAddress,
            address(GSM),
            address(registrySepolia)
        );

        GSM.setCrosssChainMessageSenderAddress(
            lendingPoolContractSepolia.getCrossChainMessageSenderAddress()
        );

        GSM.setAllowedChains(address(lendingPoolContractSepolia));
        GSM.setAllowedChains(
            address(lendingPoolContractSepolia.getCCIPRequestHanlderAddress())
        );
        interestRateModelSepolia.setLendingPoolContract(
            address(lendingPoolContractSepolia)
        );
        interestRateModelSepolia.transferOwnership(
            address(lendingPoolContractSepolia)
        );
        stableCoinSepolia.transferOwnership(
            address(lendingPoolContractSepolia)
        );
        lpTokenSepolia.transferOwnership(address(lendingPoolContractSepolia));
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

        address senderCCIPAddress = lendingPoolContractSepolia
            .getCrossChainMessageSenderAddress();

        vaultSepoliaAddress = lendingPoolContractSepolia.getVaultAddress();

        address crossChainMessageReceiverAddressSepolia = lendingPoolContractSepolia
                .getCrossChainMessageReceiverAddress();

        vm.deal(
            lendingPoolContractSepolia.getCrossChainMessageSenderAddress(),
            100 ether
        );

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
        InterestRateModel interestRateModelArbSepolia = new InterestRateModel();
        StableCoin stableCoinArbSepolia = new StableCoin();
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
        lendingPoolContractArbSepolia = new LendingPoolContract(
            tokenAddressArbSepolia,
            priceFeedAddressArbSepolia,
            chainIdArbSepolia,
            address(stableCoinArbSepolia),
            address(lpTokenArbSepolia),
            address(interestRateModelArbSepolia),
            arbSepoliaNetworkDetails.linkAddress,
            arbSepoliaNetworkDetails.routerAddress,
            address(0),
            address(arbSepoliaRegistry)
        );
        lendingPoolContractArbSepolia.setallowListedSenders(senderCCIPAddress);
        interestRateModelArbSepolia.setLendingPoolContract(
            address(lendingPoolContractArbSepolia)
        );
        interestRateModelArbSepolia.transferOwnership(
            address(lendingPoolContractArbSepolia)
        );
        stableCoinArbSepolia.transferOwnership(
            address(lendingPoolContractArbSepolia)
        );
        lpTokenArbSepolia.transferOwnership(
            address(lendingPoolContractArbSepolia)
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

        address crossChainMessageSenderAddressArbSepolia = lendingPoolContractArbSepolia
                .getCrossChainMessageSenderAddress();

        address crossChainMessageReceiverAddressArbSepolia = lendingPoolContractArbSepolia
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
    }

    function testIstrue() public {
        vm.selectFork(arbSepoliaFork);

        vm.startPrank(user);
        BurnMintERC677(wethArbSepolia).approve(vaultArbSepoliaAddress, 1 ether);
        lendingPoolContractArbSepolia.depositLiquidity(0, 1 ether);
        vm.selectFork(sepoliaFork);

        vm.startPrank(user);
        BurnMintERC677(wethSepolia).approve(vaultSepoliaAddress, 1 ether);

        lendingPoolContractSepolia.depositLiquidity(0, 1 ether);

        uint256 fees = lendingPoolContractSepolia.getFee(
            arbCrossChainReceiverAddress,
            0,
            1 ether,
            true,
            arbSepoliaNetworkDetails.chainSelector,
            ""
        );
        IERC20(sepoliaNetworkDetails.linkAddress).approve(
            address(lendingPoolContractSepolia),
            fees
        );

        lendingPoolContractSepolia.transferTokensFromOneChainToOtherChain(
            arbCrossChainReceiverAddress,
            arbSepoliaNetworkDetails.chainSelector,
            0,
            1 ether,
            true,
            ""
        );
        vm.stopPrank();

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);
        uint256 balance = lendingPoolContractArbSepolia.getUserBalance(user, 0);
        assertEq(balance, 2 ether);
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
}
