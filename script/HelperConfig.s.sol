// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 1000e8;
    int256 public constant BTC_USD_PRICE = 2000e8;
    struct NetworkConfig {
        address wethPriceFeedAddress;
        address wbtcPriceFeedAddress;
        address wbtc;
        address weth;
        uint256 deployerKey;
    }
    NetworkConfig public activeNetworkConfig;

    uint256 public DEFAULT_ANVIL_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        activeNetworkConfig = getOrCreateAnvilConfig();
    }

    function getOrCreateAnvilConfig()
        public
        returns (NetworkConfig memory anvilNetworkConfig)
    {
        if (activeNetworkConfig.wethPriceFeedAddress != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeedAddress = new MockV3Aggregator(
            DECIMALS,
            ETH_USD_PRICE
        );
        ERC20Mock weth = new ERC20Mock();
        MockV3Aggregator btcUsdPriceFeedAddress = new MockV3Aggregator(
            DECIMALS,
            BTC_USD_PRICE
        );
        ERC20Mock wbtc = new ERC20Mock();
        vm.stopBroadcast();
        anvilNetworkConfig = NetworkConfig({
            wethPriceFeedAddress: address(ethUsdPriceFeedAddress),
            wbtcPriceFeedAddress: address(btcUsdPriceFeedAddress),
            wbtc: address(wbtc),
            weth: address(weth),
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }
}
