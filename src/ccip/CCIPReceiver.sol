pragma solidity ^0.8.20;
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {LendingPoolContract} from "../LendingPoolContract.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {ICCIPReceiver} from "./interfaces/ICCIPReceiver.sol";
import {IGlobalStateManager} from "../interfaces/IGlobalStateManager.sol";
import {ILendingPoolContract} from "../interfaces/ILendingPoolContract.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICCIPRequestHandler} from "./interfaces/ICCIPRequestHandler.sol";
import {console} from "forge-std/console.sol";
import {IStateAggregator} from "../interfaces/IStateAggregator.sol";
import {CollateralStateMirror} from "../StateMirror/CollateralStateMirror.sol";
import {LoanManager} from "../GSM/LoanManager.sol";

contract CCIPReceiver is Ownable, ICCIPReceiver {
    event MessageAndTokenReceived(
        address sender,
        address token,
        uint256 amount,
        bytes32 messageId
    );
    event MessageReceivedForCollateralUpdate();
    error OnlyOwnerCanCall();
    error InvalidChain__OnlyEthSupported();
    uint256 ethChainId = 11155111;
    LendingPoolContract.CrossChainPayLoad public actionPayLoad;

    LendingPoolContract.CrossChainResponsePayLoad public responsePayLoad;

    address private lendingPoolContract;

    address lastToken;
    uint256 lastAmount;
    IRegistry registry;
    IGlobalStateManager GSM;
    ICCIPRequestHandler ccipRequestHandler;
    IStateAggregator stateAggregator;
    constructor(
        address lendingPoolContract_,
        address registry_,
        address ccipRequestHandler_,
        address stateAggregator_
    ) Ownable(msg.sender) {
        lendingPoolContract = lendingPoolContract_;
        registry = IRegistry(registry_);
        ccipRequestHandler = ICCIPRequestHandler(ccipRequestHandler_);
        stateAggregator = IStateAggregator(stateAggregator_);
    }
    function ccipReceiver(Client.Any2EVMMessage memory message) external {
        console.log("reached here 2");
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
        }
        else if (block.chainid == ethChainId) {
            if (
                actionPayLoad.actionType ==
                LendingPoolContract.ActionType.DEPOSIT_COLLATERAL
            ) {
                ccipRequestHandler.updateDepositCollateralDetailsOfUser(
                    actionPayLoad
                );

                address receiver = registry.getCrossChainAddress(
                    message.sourceChainSelector,
                    "crossChainMessageReceiverAddress"
                );
                ccipRequestHandler.updateCollateralStateMirror(
                    receiver,
                    actionPayLoad.chainId,
                    actionPayLoad.user,
                    actionPayLoad.crossChaintokenId,
                    message.sourceChainSelector
                );
                emit MessageReceivedForCollateralUpdate();
            }
            else if (
                actionPayLoad.actionType ==
                LendingPoolContract.ActionType.LOAN_TAKEN
            ) {
                ccipRequestHandler.updateBorrowLoanDetailsOfUser(actionPayLoad);
                address receiver = registry.getCrossChainAddress(
                    message.sourceChainSelector,
                    "crossChainMessageReceiverAddress"
                );
                ccipRequestHandler.updateLoanStateMirror(
                    receiver,
                    actionPayLoad.chainId,
                    actionPayLoad.user,
                    actionPayLoad.crossChaintokenId,
                    abi
                        .decode(
                            actionPayLoad.extraInformation,
                            (LoanManager.LoanDetails)
                        )
                        .loanId,
                    message.sourceChainSelector
                );
            } else if (
                actionPayLoad.actionType ==
                LendingPoolContract.ActionType.DEPOSIT_LIQUIDITY
            ) {
                ccipRequestHandler.updateDepositDetailsOfUser(
                    actionPayLoad.chainId,
                    actionPayLoad.user,
                    actionPayLoad.crossChaintokenId,
                    actionPayLoad.amountToTransfer
                );
                ccipRequestHandler.updateLPTokensInCirculation(
                    actionPayLoad.chainId,
                    actionPayLoad.user,
                    abi.decode(actionPayLoad.extraInformation, (uint256))
                );
                address receiver = registry.getCrossChainAddress(
                    message.sourceChainSelector,
                    "crossChainMessageReceiverAddress"
                );
                ccipRequestHandler.mirrorUpdateOfTheUserDeposit(
                    receiver,
                    actionPayLoad.chainId,
                    actionPayLoad.user,
                    actionPayLoad.crossChaintokenId,
                    message.sourceChainSelector
                );
            } else if (
                actionPayLoad.actionType ==
                LendingPoolContract.ActionType.WITHDRAW_LIQUIDITY
            ) {
                ccipRequestHandler.updateWithdrawDepositDetailsOfUser(
                    actionPayLoad.chainId,
                    actionPayLoad.user,
                    actionPayLoad.crossChaintokenId,
                    actionPayLoad.amountToTransfer
                );
                address receiver = registry.getCrossChainAddress(
                    message.sourceChainSelector,
                    "crossChainMessageReceiverAddress"
                );

                ccipRequestHandler.mirrorUpdateOfTheUserDeposit(
                    receiver,
                    actionPayLoad.chainId,
                    actionPayLoad.user,
                    actionPayLoad.crossChaintokenId,
                    message.sourceChainSelector
                );
            } else if (
                actionPayLoad.actionType ==
                LendingPoolContract.ActionType.WITHDRAW_COLLATERAL
            ) {
                ccipRequestHandler.updateWithdrawDepositCollateralDetailsOfUser(
                        actionPayLoad
                    );
                address receiver = registry.getCrossChainAddress(
                    message.sourceChainSelector,
                    "crossChainMessageReceiverAddress"
                );
                ccipRequestHandler.updateCollateralStateMirror(
                    receiver,
                    actionPayLoad.chainId,
                    actionPayLoad.user,
                    actionPayLoad.crossChaintokenId,
                    message.sourceChainSelector
                );
            } else if (
                actionPayLoad.actionType ==
                LendingPoolContract.ActionType.LOAN_REPAYMENT
            ) {
                ccipRequestHandler.repayLoanDetailsOfUser(actionPayLoad);
                address receiver = registry.getCrossChainAddress(
                    message.sourceChainSelector,
                    "crossChainMessageReceiverAddress"
                );
                ccipRequestHandler.updateLoanStateMirror(
                    receiver,
                    abi
                        .decode(
                            actionPayLoad.extraInformation,
                            (LoanManager.LoanDetails)
                        )
                        .loanChainId,
                    actionPayLoad.user,
                    actionPayLoad.crossChaintokenId,
                    abi
                        .decode(
                            actionPayLoad.extraInformation,
                            (LoanManager.LoanDetails)
                        )
                        .loanId,
                    message.sourceChainSelector
                );
            }
        }
        else {
            if (
                responsePayLoad.response ==
                LendingPoolContract
                    .Response
                    .RESPONSE_COLLATERAL_INFORMATION_FOR_USER
            ) {
                stateAggregator.updateCollateralDetailsOfUser(
                    responsePayLoad.chainId,
                    responsePayLoad.user,
                    responsePayLoad.crossChainTokenId,
                    CollateralStateMirror.CollateralDetailsOfUser({
                        amount: responsePayLoad.amount,
                        lastUpdatedTime: responsePayLoad.timeOfResponse
                    })
                );
            }
            else if (
                responsePayLoad.response ==
                LendingPoolContract.Response.RESPONSE_LOAN_INFORMATION_FOR_USER
            ) {
                console.log("reached here 1");
                (
                    LoanManager.LoanDetails memory loanInfo,
                    uint256 borrowerIndex
                ) = abi.decode(
                        responsePayLoad.extraInformation,
                        (LoanManager.LoanDetails, uint256)
                    );
                stateAggregator.updateLoanDetailsOfUser(
                    responsePayLoad.chainId,
                    responsePayLoad.user,
                    responsePayLoad.crossChainTokenId,
                    loanInfo.loanId,
                    loanInfo
                );
                stateAggregator.updateBorrowerIndex(
                    responsePayLoad.crossChainTokenId,
                    borrowerIndex
                );
            } else if (
                responsePayLoad.response ==
                LendingPoolContract
                    .Response
                    .RESPONSE_DEPOSIT_INFORMATION_FOR_USER
            ) {
                stateAggregator.updateDepositDetailsOfUser(
                    responsePayLoad.chainId,
                    responsePayLoad.user,
                    responsePayLoad.crossChainTokenId,
                    responsePayLoad.amount
                );
                (
                    uint256 lpTokenPerUser,
                    uint256 lpTokenPerUserPerChain,
                    uint256 totalLpTokenInChain,
                    uint256 lpTokensInCirculation,
                    uint256 borrowerIndex
                ) = abi.decode(
                        responsePayLoad.extraInformation,
                        (uint256, uint256, uint256, uint256, uint256)
                    );
                stateAggregator.updateLpTokensForAUser(
                    responsePayLoad.user,
                    lpTokenPerUser
                );
                stateAggregator.updateLpTokensPerUserPerChain(
                    responsePayLoad.chainId,
                    responsePayLoad.user,
                    lpTokenPerUserPerChain
                );
                stateAggregator.updateTotalLpTokensInAChain(
                    responsePayLoad.chainId,
                    totalLpTokenInChain
                );
                stateAggregator.updateLpTokenInCirculation(
                    lpTokensInCirculation
                );
                stateAggregator.updateBorrowerIndex(
                    responsePayLoad.crossChainTokenId,
                    borrowerIndex
                );
            } else if (
                responsePayLoad.response ==
                LendingPoolContract.Response.RESPONSE_SET_INITAL_PARAMS
            ) {
                (uint64 tokenId, uint256 borrowerIndex) = abi.decode(
                    responsePayLoad.extraInformation,
                    (uint64, uint256)
                );
                stateAggregator.updateBorrowerIndex(tokenId, borrowerIndex);
            } else {
                console.log("No information found");
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

    /**
     * @notice Overrides the chain ids this contract treats as the hub.
     *
     * The ids default to the live testnet values, so existing deployments and
     * the integration tests are unaffected. A local deployment calls this to run
     * the hub on an id that does not collide with a wallet's built-in networks —
     * MetaMask reserves 11155111 for its own Sepolia and will not let a custom
     * RPC own it, which makes gas estimation resolve against the wrong chain.
     */
    function setChainIds(uint256 ethChainId_) external onlyOwner {
        ethChainId = ethChainId_;
    }
}
