// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, Vm, console} from "forge-std/Test.sol";

import {CrossChainMessageSender} from "../../src/ccip/CrossChainMessageSender.sol";
import {CrossChainMessageReceiver} from "../../src/ccip/CrossChainMessageReceiver.sol";

import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {BurnMintERC677Helper} from "@chainlink/local/src/ccip/BurnMintERC677Helper.sol";

contract Demo is Test {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    CrossChainMessageSender public sender;
    CrossChainMessageReceiver public receiver;
    BurnMintERC677Helper public ccipBnMEthSepolia;
    // BurnMintERC677Helper public ccipBnMEthSepolia;

    Register.NetworkDetails sepoliaNetworkDetails;

    Register.NetworkDetails arbSepoliaNetworkDetails;

    uint256 sepoliaFork;

    uint256 arbSepoliaFork;

    function setUp() public {
        sepoliaFork = vm.createSelectFork("eth");
        arbSepoliaFork = vm.createFork("arb");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(
            block.chainid
        );
        ccipBnMEthSepolia = BurnMintERC677Helper(
            sepoliaNetworkDetails.ccipBnMAddress
        );

        sender = new CrossChainMessageSender(
            sepoliaNetworkDetails.linkAddress,
            sepoliaNetworkDetails.routerAddress
        );
        ccipBnMEthSepolia.drip(address(sender));
        // receiver = new CrossChainMessageReceiver();

        ccipLocalSimulatorFork.requestLinkFromFaucet(address(sender), 5 ether);

        vm.selectFork(arbSepoliaFork);

        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(
            block.chainid
        );

        receiver = new CrossChainMessageReceiver(
            arbSepoliaNetworkDetails.routerAddress
        );

        receiver.allowListedSender(address(sender), true);
    }

    function testFork() public {
        vm.selectFork(sepoliaFork);

        string memory someText = "hello forking";

        uint256 amountToSend = 1 ether;

        // sender.sendViaLink(
        //     address(receiver),
        //     someText,
        //     arbSepoliaNetworkDetails.chainSelector,
        //     sepoliaNetworkDetails.ccipBnMAddress,
        //     amountToSend
        // );

        uint256 fees = sender.getFee(
            address(receiver),
            someText,
            arbSepoliaNetworkDetails.chainSelector,
            sepoliaNetworkDetails.ccipBnMAddress,
            amountToSend
        );

        vm.deal(address(sender), fees);

        sender.sendViaNativeToken(
            address(receiver),
            someText,
            arbSepoliaNetworkDetails.chainSelector,
            sepoliaNetworkDetails.ccipBnMAddress,
            amountToSend
        );

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        assertEq(amountToSend, receiver.getLastSendAmount());
    }
}
