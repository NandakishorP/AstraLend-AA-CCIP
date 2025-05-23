// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// import {Test, console} from "forge-std/Test.sol";
// import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
// import {LendingPoolContract} from "../../src/LendingPoolContract.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {InterestRateModel} from "../../src/InterestRate/InterestRateModel.sol";
// import {LpToken} from "../../src/tokens/LpTokenContract.sol";
// import {StableCoin} from "../../src/tokens/StableCoin.sol";
// import {IRouterClient, Client} from "@chainlink-local/lib/chainlink-ccip/chains/evm/contracts/interfaces/IRouterClient.sol";
// import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// contract CrossChainLending is Test {
//     uint256 sepoliaFork;
//     uint256 arbSepoliaFork;
//     address owner = makeAddr("owner");
//     address user = makeAddr("user");
//     uint256 public constant STARTING_USER_BALANCE = 20 ether;
//     uint256 public constant DEPOSITING_AMOUNT = 5 ether;
//     CCIPLocalSimulatorFork ccipLocalSimulatorFork;
//     Register.NetworkDetails sepoliaNetworkDetails;
//     Register.NetworkDetails arbSepoliaNetworkDetails;
//     LendingPoolContract lendingPoolcontractSepolia;
//     LendingPoolContract lendingPoolcontractarbSepolia;
//     address wethPriceFeedAddressSepolia;
//     address wethPriceFeedAddressarbSepolia;
//     address wbtcPriceFeedAddressSepolia;
//     address wbtcPriceFeedAddressarbSepolia;
//     address[] public tokenAddressesarbSepolia;
//     address[] public tokenAddressesSepolia;
//     address[] public priceFeedAddressesSepolia;
//     address[] public priceFeedAddressesarbSepolia;
//     HelperConfig helperConfigSepolia;
//     HelperConfig helperConfigarbSepolia;

//     address vaultSepolia;
//     address vaultarbSepolia;

//     address wethSepolia;
//     address wbtcSepolia;
//     address wetharbSepolia;
//     address wbtcarbSepolia;

//     function setUp() public {
//         sepoliaFork = vm.createSelectFork("eth");
//         arbSepoliaFork = vm.createFork("arb");
//         ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
//         vm.makePersistent(address(ccipLocalSimulatorFork));
//         sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(
//             block.chainid
//         );
//         helperConfigSepolia = new HelperConfig();
//         (
//             wethPriceFeedAddressSepolia,
//             wbtcPriceFeedAddressSepolia,
//             wethSepolia,
//             wbtcSepolia,

//         ) = helperConfigSepolia.activeNetworkConfig();

//         tokenAddressesSepolia = [wethSepolia, wbtcSepolia];
//         priceFeedAddressesSepolia = [
//             wethPriceFeedAddressSepolia,
//             wbtcPriceFeedAddressSepolia
//         ];
//         vm.startPrank(owner);

//         InterestRateModel interestRateModelSepolia = new InterestRateModel();
//         StableCoin stableCoinSepolia = new StableCoin();
//         LpToken lpTokenSepolia = new LpToken();
//         ERC20Mock(wethSepolia).mint(user, STARTING_USER_BALANCE);

//         lendingPoolcontractSepolia = new LendingPoolContract(
//             tokenAddressesSepolia,
//             priceFeedAddressesSepolia,
//             address(stableCoinSepolia),
//             address(lpTokenSepolia),
//             address(interestRateModelSepolia),
//             sepoliaNetworkDetails.routerAddress,
//             sepoliaNetworkDetails.chainSelector,
//             sepoliaNetworkDetails.linkAddress
//         );
//         vaultSepolia = lendingPoolcontractSepolia.getVaultAddress();

//         interestRateModelSepolia.setLendingPoolContract(
//             address(lendingPoolcontractSepolia)
//         );
//         interestRateModelSepolia.transferOwnership(
//             address(lendingPoolcontractSepolia)
//         );
//         stableCoinSepolia.transferOwnership(
//             address(lendingPoolcontractSepolia)
//         );
//         lpTokenSepolia.transferOwnership(address(lendingPoolcontractSepolia));
//         vm.stopPrank();

//         vm.selectFork(arbSepoliaFork);

//         arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(
//             block.chainid
//         );
//         helperConfigarbSepolia = new HelperConfig();
//         (
//             wethPriceFeedAddressarbSepolia,
//             wbtcPriceFeedAddressarbSepolia,
//             wetharbSepolia,
//             wbtcarbSepolia,

//         ) = helperConfigarbSepolia.activeNetworkConfig();

//         console.log("done");

//         tokenAddressesarbSepolia = [wetharbSepolia, wbtcarbSepolia];
//         priceFeedAddressesarbSepolia = [
//             wethPriceFeedAddressarbSepolia,
//             wbtcPriceFeedAddressarbSepolia
//         ];

//         vm.startPrank(owner);

//         InterestRateModel interestRateModelarbSepolia = new InterestRateModel();
//         StableCoin stableCoinarbSepolia = new StableCoin();
//         LpToken lpTokenarbSepolia = new LpToken();

//         lendingPoolcontractarbSepolia = new LendingPoolContract(
//             tokenAddressesarbSepolia,
//             priceFeedAddressesarbSepolia,
//             address(stableCoinarbSepolia),
//             address(lpTokenarbSepolia),
//             address(interestRateModelarbSepolia),
//             arbSepoliaNetworkDetails.routerAddress,
//             arbSepoliaNetworkDetails.chainSelector,
//             arbSepoliaNetworkDetails.linkAddress
//         );
//         vaultarbSepolia = lendingPoolcontractarbSepolia.getVaultAddress();

//         console.log(
//             "lendingPoolcontractaebSepolia",
//             address(lendingPoolcontractarbSepolia)
//         );
//         interestRateModelarbSepolia.setLendingPoolContract(
//             address(lendingPoolcontractarbSepolia)
//         );
//         interestRateModelarbSepolia.transferOwnership(
//             address(lendingPoolcontractarbSepolia)
//         );
//         stableCoinarbSepolia.transferOwnership(
//             address(lendingPoolcontractarbSepolia)
//         );
//         lpTokenarbSepolia.transferOwnership(
//             address(lendingPoolcontractarbSepolia)
//         );
//         vm.stopPrank();
//     }

//     // function transferTokens(
//     //     uint256 amountToSend,
//     //     uint256 localFork,
//     //     uint256 remoteFork,
//     //     address localToken,
//     //     address remoteToken,
//     //     Register.NetworkDetails memory localNetworkDetails,
//     //     Register.NetworkDetails memory remoteNetworkDetails,
//     //     LendingPoolContract loaclLendingPool,
//     //     LendingPoolContract remoteLendingPool
//     // ) public {
//     //     vm.selectFork(localFork);

//     //     v
//     // }
//     // function _buildCCIPMessage(
//     //     address _receiver,
//     //     bytes memory _data,
//     //     address _token,
//     //     uint256 _amount
//     // ) private pure returns (Client.EVM2AnyMessage memory) {
//     //     Client.EVMTokenAmount[] memory tokenAmounts;
//     //     if (_token != address(0) && _amount > 0) {
//     //         tokenAmounts = new Client.EVMTokenAmount[](1);
//     //         tokenAmounts[0] = Client.EVMTokenAmount({
//     //             token: _token,
//     //             amount: _amount
//     //         });
//     //     } else {
//     //         tokenAmounts = new Client.EVMTokenAmount[](0);
//     //     }
//     //     return
//     //         Client.EVM2AnyMessage({
//     //             receiver: abi.encode(_receiver),
//     //             data: _data,
//     //             tokenAmounts: tokenAmounts,
//     //             extraArgs: Client._argsToBytes(
//     //                 Client.EVMExtraArgsV2({
//     //                     gasLimit: 100_000,
//     //                     allowOutOfOrderExecution: false
//     //                 })
//     //             ),
//     //             feeToken: address(0)
//     //         });
//     // }

//     enum ActionType {
//         DEPOSIT,
//         TRANSFER,
//         BORROW,
//         REPAY
//     }

//     struct CrossChainPayload {
//         ActionType action;
//         address user;
//         string message;
//     }

//     function testTransferTokens() public {
//         vm.selectFork(arbSepoliaFork);

//         uint64 destinationChainSelector = arbSepoliaNetworkDetails
//             .chainSelector;
//         address _receiver = lendingPoolcontractarbSepolia
//             .getCCIPMessageReceiverAddress();

//         vm.selectFork(sepoliaFork);

//         vm.startPrank(user);
//         ERC20Mock(wethSepolia).approve(
//             address(vaultSepolia),
//             DEPOSITING_AMOUNT
//         );

//         lendingPoolcontractSepolia.depositLiquidity(
//             wethSepolia,
//             DEPOSITING_AMOUNT
//         );

//         // uint256 fee = lendingPoolcontractSepolia.getFees(
//         //     destinationChainSelector,
//         //     wethSepolia,
//         //     DEPOSITING_AMOUNT
//         // );

//         Client.EVMTokenAmount[]
//             memory tokenAmounts = new Client.EVMTokenAmount[](1);
//         tokenAmounts[0] = Client.EVMTokenAmount({
//             token: wethSepolia,
//             amount: DEPOSITING_AMOUNT
//         });
//         bytes memory _data = abi.encode(
//             CrossChainPayload({
//                 action: ActionType.TRANSFER,
//                 user: msg.sender,
//                 message: ""
//             })
//         );

//         Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
//             receiver: abi.encode(_receiver),
//             data: _data,
//             tokenAmounts: tokenAmounts,
//             extraArgs: Client._argsToBytes(
//                 Client.EVMExtraArgsV1({gasLimit: 200_000})
//             ),
//             feeToken: address(0)
//         });

//         uint256 fee = IRouterClient(sepoliaNetworkDetails.routerAddress).getFee(
//             destinationChainSelector,
//             message
//         );

//         lendingPoolcontractSepolia.crossChainTransferOfTokens{value: fee}(
//             wethSepolia,
//             DEPOSITING_AMOUNT,
//             destinationChainSelector,
//             true
//         );

//         vm.stopPrank();
//     }
// }
