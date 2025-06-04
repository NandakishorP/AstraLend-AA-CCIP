// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {LendingPoolContract} from "../LendingPoolContract.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {ICCIPResponseHandler} from "./interfaces/ICCIPResponseHandler.sol";
import {IGlobalStateManager} from "../interfaces/IGlobalStateManager.sol";
import {ILendingPoolContract} from "../interfaces/ILendingPoolContract.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICCIPRequestHandler} from "./interfaces/ICCIPRequestHandler.sol";
import {console} from "forge-std/console.sol";

contract CCIPResponseHandler is Ownable, ICCIPResponseHandler {
    event MessageAndTokenReceived(
        address sender,
        address token,
        uint256 amount,
        bytes32 messageId
    );
    event MessageReceivedForCollateralUpdate();
    error OnlyOwnerCanCall();
    error InvalidChain__OnlyEthSupported();
    uint256 ethChainId = 11155111; // for sepolia now
    LendingPoolContract.CrossChainPayLoad public actionPayLoad;
    LendingPoolContract.CrossChainRequestPayLoad public requestPayLoad;
    LendingPoolContract.CrossChainResponsePayLoad public responsePayLoad;
    address private lendingPoolContract;
    address lastToken;
    uint256 lastAmount;
    IRegistry registry;
    IGlobalStateManager GSM;
    ICCIPRequestHandler ccipRequestHandler;

    constructor(
        address lendingPoolContract_,
        address registry_,
        address ccipRequestHandler_
    ) Ownable(msg.sender) {
        lendingPoolContract = lendingPoolContract_;
        registry = IRegistry(registry_);

        ccipRequestHandler = ICCIPRequestHandler(ccipRequestHandler_);
    }

    function ccipReceiver(Client.Any2EVMMessage memory message) external {
        bytes memory rawData = message.data;

        uint64 id;
        assembly {
            id := mload(add(rawData, 32))
        }

        if (id == 0) {
            (, actionPayLoad) = abi.decode(
                message.data,
                (uint64, LendingPoolContract.CrossChainPayLoad)
            );
        } else if (id == 1) {
            (, requestPayLoad) = abi.decode(
                message.data,
                (uint64, LendingPoolContract.CrossChainRequestPayLoad)
            );
        } else if (id == 2) {
            (, responsePayLoad) = abi.decode(
                message.data,
                (uint64, LendingPoolContract.CrossChainResponsePayLoad)
            );
        }

        if (message.destTokenAmounts.length > 0) {
            if (
                actionPayLoad.actionType ==
                LendingPoolContract.ActionType.TRANSFER
            ) {
                transferTokens(message);
            }

            lastToken = message.destTokenAmounts[0].token;
            lastAmount = message.destTokenAmounts[0].amount;

            emit MessageAndTokenReceived(
                abi.decode(message.sender, (address)),
                lastToken,
                lastAmount,
                message.messageId
            );
        } else if (block.chainid == ethChainId) {
            if (
                actionPayLoad.actionType ==
                LendingPoolContract.ActionType.DEPOSIT_COLLATERAL
            ) {
                ccipRequestHandler.updateCollateralDetailsOfUser(actionPayLoad);
                emit MessageReceivedForCollateralUpdate();
            } else if (
                requestPayLoad.request ==
                LendingPoolContract
                    .Request
                    .REQUEST_COLLATERAL_INFORMATION_FOR_USER
            ) {
                ccipRequestHandler.getCollateralInformation(
                    message,
                    requestPayLoad
                );
            }
        } else {
            if (
                responsePayLoad.response ==
                LendingPoolContract
                    .Response
                    .RESPONSE_COLLATERAL_INFORMATION_FOR_USER
            ) {
                uint256 balance = responsePayLoad.amount;
                ILendingPoolContract(lendingPoolContract)
                    .updateCollateralDetailsCrossChain(
                        responsePayLoad.requestId,
                        balance
                    );
            }
        }
    }

    function sliceBytes(
        bytes memory data,
        uint256 start
    ) internal pure returns (bytes memory result) {
        require(start <= data.length, "Invalid start");
        uint256 len = data.length - start;
        assembly {
            result := mload(0x40)
            mstore(result, len)

            let dataPtr := add(add(data, 32), start)
            let resultPtr := add(result, 32)

            for {
                let i := 0
            } lt(i, len) {
                i := add(i, 32)
            } {
                mstore(add(resultPtr, i), mload(add(dataPtr, i)))
            }

            mstore(0x40, add(resultPtr, and(add(len, 31), not(31))))
        }
    }

    function transferTokens(Client.Any2EVMMessage memory message) private {
        address tokenAddress = ILendingPoolContract(lendingPoolContract)
            .getTokenAddressFromTokenId(actionPayLoad.crossChaintokenId);

        IERC20(tokenAddress).approve(
            address(lendingPoolContract),
            actionPayLoad.amountToTransfer
        );
        ILendingPoolContract(lendingPoolContract)
            .receiveTokensFromOneChainToOther(message.data);
    }
}
