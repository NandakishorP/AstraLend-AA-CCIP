// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IGlobalStateManager} from "../interfaces/IGlobalStateManager.sol";
import {ILendingPoolContract} from "../interfaces/ILendingPoolContract.sol";
import {LendingPoolContract} from "../LendingPoolContract.sol";
import {ICrossChainMessageSender} from "../ccip/interfaces/ICrossChainMessageSender.sol";
import {CollateralControllerErrors} from "../errors/Errors.sol";
import {IStateAggregator} from "../interfaces/IStateAggregator.sol";
import {ICollateralController} from "./interfaces/ICollateralController.sol";

contract CollateralController is Ownable, ICollateralController {
    IRegistry registry;
    IVault vault;
    ILendingPoolContract lendingPoolContract;
    IStateAggregator stateAggregator;

    IGlobalStateManager GSM;

    uint256 ethChainId = 11155111;

    uint256 arbChainId = 421614;

    constructor(
        address registry_,
        address vault_,
        address gsm_,
        address lendingPoolContract_,
        address stateAggregator_
    ) Ownable(msg.sender) {
        registry = IRegistry(registry_);
        vault = IVault(vault_);
        GSM = IGlobalStateManager(gsm_);
        lendingPoolContract = ILendingPoolContract(lendingPoolContract_);
        stateAggregator = IStateAggregator(stateAggregator_);
    }

    function depositCollateral(
        address tokenAddress,
        uint64 tokenId,
        address sender,
        uint256 amount
    ) external payable onlyOwner {
        uint64 ethDestinationChainSelector = registry
            .getDestinationChainSelector(ethChainId);
        vault.depositCollateral(sender, tokenAddress, amount);

        if (ethChainId == block.chainid) {
            GSM.updateDepositCollateralOfUser(
                block.chainid,
                sender,
                tokenId,
                amount
            );
            uint64 arbDestinationChainSelector = registry
                .getDestinationChainSelector(arbChainId);
            address arbCrossChainReceiverAddress = registry
                .getCrossChainAddress(
                    arbDestinationChainSelector,
                    "crossChainMessageReceiverAddress"
                );

            GSM.mirrorUpdateOfTheUserCollateral(
                arbCrossChainReceiverAddress,
                block.chainid,
                sender,
                tokenId,
                arbDestinationChainSelector
            );
        } else {
            address crossChainMessageSender = registry.getAddress(
                block.chainid,
                "crossChainMessageSenderAddress"
            );

            address receiver = registry.getCrossChainAddress(
                ethDestinationChainSelector,
                "crossChainMessageReceiverAddress"
            );

            bytes memory data = abi.encode(
                lendingPoolContract.getActionCommunicationId(),
                LendingPoolContract.CrossChainPayLoad({
                    actionType: LendingPoolContract
                        .ActionType
                        .DEPOSIT_COLLATERAL,
                    chainId: block.chainid,
                    user: sender,
                    crossChaintokenId: tokenId,
                    amountToTransfer: amount,
                    messageToTransfer: "",
                    extraInformation: ""
                })
            );

            uint256 fees = ICrossChainMessageSender(crossChainMessageSender)
                .getFee(
                    receiver,
                    data,
                    ethDestinationChainSelector,
                    address(0),
                    0,
                    false
                );

            if (msg.value < fees) {
                revert CollateralControllerErrors
                    .CollateralController__InsufficentFees();
            }

            (bool success, ) = payable(address(crossChainMessageSender)).call{
                value: fees
            }("");

            if (!success) {
                revert CollateralControllerErrors
                    .CollateralController__TransferFailed();
            }

            ICrossChainMessageSender(crossChainMessageSender)
                .sendViaNativeToken(
                    receiver,
                    data,
                    ethDestinationChainSelector,
                    address(0),
                    amount
                );
        }

        emit LendingPoolContract.CollateralDeposited(
            sender,
            tokenAddress,
            amount
        );
    }

    function withDrawCollateralController(
        address user,
        address tokenAddress,
        uint64 tokenId,
        uint256 amount
    ) external payable {
        bool chainIdentifier = block.chainid == ethChainId;

        uint256 collateralAmount = chainIdentifier
            ? GSM.getUserCollateralDetails(block.chainid, user, tokenId)
            : stateAggregator.readCollateralDetailsOfUser(
                block.chainid,
                user,
                tokenId
            );

        if (collateralAmount < amount) {
            revert CollateralControllerErrors
                .CollateralContorller__InvalidRequestAmount();
        }

        if (chainIdentifier) {
            GSM.updateWithdrawCollateralOfUser(
                block.chainid,
                user,
                tokenId,
                amount
            );

            uint64 arbDestinationChainSelector = registry
                .getDestinationChainSelector(arbChainId);

            address arbCrossChainReceiverAddress = registry
                .getCrossChainAddress(
                    arbDestinationChainSelector,
                    "crossChainMessageReceiverAddress"
                );

            GSM.mirrorUpdateOfTheUserCollateral(
                arbCrossChainReceiverAddress,
                block.chainid,
                user,
                tokenId,
                arbDestinationChainSelector
            );
        } else {
            uint64 ethDestinationChainSelector = registry
                .getDestinationChainSelector(ethChainId);

            address receiver = registry.getCrossChainAddress(
                ethDestinationChainSelector,
                "crossChainMessageReceiverAddress"
            );

            bytes memory data = abi.encode(
                lendingPoolContract.getActionCommunicationId(),
                LendingPoolContract.CrossChainPayLoad({
                    actionType: LendingPoolContract
                        .ActionType
                        .WITHDRAW_COLLATERAL,
                    chainId: block.chainid,
                    user: user,
                    crossChaintokenId: tokenId,
                    amountToTransfer: amount,
                    messageToTransfer: "",
                    extraInformation: ""
                })
            );

            address crossChainMessageSender = registry.getAddress(
                block.chainid,
                "crossChainMessageSenderAddress"
            );

            uint256 fees = ICrossChainMessageSender(crossChainMessageSender)
                .getFee(
                    receiver,
                    data,
                    ethDestinationChainSelector,
                    address(0),
                    amount,
                    false
                );

            if (msg.value < fees) {
                revert CollateralControllerErrors
                    .CollateralController__InsufficentFees();
            }

            (bool success, ) = payable(address(crossChainMessageSender)).call{
                value: fees
            }("");

            if (!success) {
                revert CollateralControllerErrors
                    .CollateralController__TransferFailed();
            }

            ICrossChainMessageSender(crossChainMessageSender)
                .sendViaNativeToken(
                    receiver,
                    data,
                    ethDestinationChainSelector,
                    address(0),
                    amount
                );
        }

        vault.transferCollateral(user, tokenAddress, amount);

        emit LendingPoolContract.CollateralWithdrawed(
            user,
            tokenAddress,
            amount
        );
    }
}
