// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {BurnMintERC677Helper, BurnMintERC677} from "@chainlink/local/src/ccip/BurnMintERC677Helper.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {LendingPoolContract} from "../../src/LendingPoolContract.sol";
import {InterestRateModel} from "../../src/InterestRate/InterestRateModel.sol";
import {StableCoin} from "../../src/tokens/StableCoin.sol";
import {LpToken} from "../../src/tokens/LpTokenContract.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
        priceFeedAddressSepolia = [address(wethUsdPriceFeedAddressSepolia)];
        InterestRateModel interestRateModelSepolia = new InterestRateModel();
        StableCoin stableCoinSepolia = new StableCoin();
        LpToken lpTokenSepolia = new LpToken();
        // 0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D

        lendingPoolContractSepolia = new LendingPoolContract(
            tokenAddressSepolia,
            priceFeedAddressSepolia,
            address(stableCoinSepolia),
            address(lpTokenSepolia),
            address(interestRateModelSepolia),
            sepoliaNetworkDetails.linkAddress,
            sepoliaNetworkDetails.routerAddress
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
        vm.stopPrank();

        wethSepolia.drip(user);
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, 5 ether);

        address senderCCIPAddress = lendingPoolContractSepolia
            .getCrossChainMessageSenderAddress();

        vaultSepoliaAddress = lendingPoolContractSepolia.getVaultAddress();

        vm.selectFork(arbSepoliaFork);

        wethUsdPriceFeedAddressArbSepolia = new MockV3Aggregator(
            DECIMALS,
            ETH_USD_PRICE
        );
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(
            block.chainid
        );
        console.log("address:", arbSepoliaNetworkDetails.ccipBnMAddress);
        wethArbSepolia = BurnMintERC677Helper(
            arbSepoliaNetworkDetails.ccipBnMAddress
        );

        vm.startPrank(ownerArbSepolia);

        tokenAddressArbSepolia = [address(wethArbSepolia)];
        priceFeedAddressArbSepolia = [
            address(wethUsdPriceFeedAddressArbSepolia)
        ];
        InterestRateModel interestRateModelArbSepolia = new InterestRateModel();
        StableCoin stableCoinArbSepolia = new StableCoin();
        LpToken lpTokenArbSepolia = new LpToken();

        lendingPoolContractArbSepolia = new LendingPoolContract(
            tokenAddressArbSepolia,
            priceFeedAddressArbSepolia,
            address(stableCoinArbSepolia),
            address(lpTokenArbSepolia),
            address(interestRateModelArbSepolia),
            arbSepoliaNetworkDetails.linkAddress,
            arbSepoliaNetworkDetails.routerAddress
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

        vm.stopPrank();
        wethArbSepolia.drip(user);
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
}
