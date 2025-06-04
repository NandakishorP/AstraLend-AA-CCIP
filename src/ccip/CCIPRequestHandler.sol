// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {LendingPoolContract} from "../LendingPoolContract.sol";
pragma solidity ^0.8.20;
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {LendingPoolContract} from "../LendingPoolContract.sol";
import {IGlobalStateManager} from "../interfaces/IGlobalStateManager.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {ILendingPoolContract} from "../interfaces/ILendingPoolContract.sol";
import {ICrossChainMessageSender} from "./interfaces/ICrossChainMessageSender.sol";
import {ICCIPRequestHandler} from "./interfaces/ICCIPRequestHandler.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";

contract CCIPRequestHandler is ICCIPRequestHandler, Ownable {
    IGlobalStateManager GSM;
    IRegistry registry;
    uint256 ethChainId = 11155111; // for sepolia now

    ICrossChainMessageSender crossChainMessageSender;
    ILendingPoolContract lendingPoolContract;
    error OnlyOwnerCanCall();
    error InvalidChain__OnlyEthSupported();

    constructor(
        address lendingPoolContract_,
        address registry_,
        address gsm_,
        address crossChainMessageSender_
    ) Ownable(msg.sender) {
        GSM = IGlobalStateManager(gsm_);
        registry = IRegistry(registry_);

        crossChainMessageSender = ICrossChainMessageSender(
            crossChainMessageSender_
        );

        lendingPoolContract = ILendingPoolContract(lendingPoolContract_);
    }

    function setGSMAddress(address gsm) external onlyOwner {
        if (block.chainid != ethChainId) {
            revert InvalidChain__OnlyEthSupported();
        }
        GSM = IGlobalStateManager(gsm);
    }

    function updateCollateralDetailsOfUser(
        LendingPoolContract.CrossChainPayLoad memory actionPayLoad
    ) external {
        GSM.updateCollateralDetailsOfUser(
            actionPayLoad.chainId,
            actionPayLoad.user,
            actionPayLoad.crossChaintokenId,
            actionPayLoad.amountToTransfer
        );
    }

    function getCollateralInformation(
        Client.Any2EVMMessage memory message,
        LendingPoolContract.CrossChainRequestPayLoad memory requestPayLoad
    ) external {
        uint256 balance = GSM.getUserCollateralDetails(
            requestPayLoad.chainId,
            requestPayLoad.user,
            requestPayLoad.crossChainTokenId
        );

        // this need to be replaced in such a way that it came from the registry

        // the fees for this should be dealed in the crossChainSenderContract

        address receiver = registry.getCrossChainAddress(
            message.sourceChainSelector,
            "crossChainMessageReceiverAddress"
        );

        crossChainMessageSender.sendViaNativeToken(
            receiver,
            abi.encode(
                ILendingPoolContract(lendingPoolContract)
                    .getResponseCommunicationId(),
                LendingPoolContract.CrossChainResponsePayLoad({
                    response: LendingPoolContract
                        .Response
                        .RESPONSE_COLLATERAL_INFORMATION_FOR_USER,
                    user: requestPayLoad.user,
                    chainId: requestPayLoad.chainId,
                    crossChainTokenId: requestPayLoad.crossChainTokenId,
                    requestId: requestPayLoad.requestId,
                    amount: balance
                })
            ),
            message.sourceChainSelector,
            address(0),
            0
        );
    }
}
