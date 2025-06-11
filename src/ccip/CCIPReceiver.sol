// SPDX-License-Identifier: MIT
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
    /**
     * @notice Emitted when a message and associated token transfer is successfully received.
     * @param sender The address that sent the message and tokens.
     * @param token The address of the ERC20 token received.
     * @param amount The amount of tokens received.
     * @param messageId The unique identifier of the received message.
     */
    event MessageAndTokenReceived(
        address sender,
        address token,
        uint256 amount,
        bytes32 messageId
    );
    /**
     * @notice Emitted when a message related to collateral update is successfully processed.
     */
    event MessageReceivedForCollateralUpdate();
    error OnlyOwnerCanCall();
    error InvalidChain__OnlyEthSupported();

    uint256 ethChainId = 11155111; // for sepolia now

    /// @notice Payload structure containing data for cross-chain action requests (e.g., loan initiation, collateral update).
    /// @dev This is populated before sending cross-chain messages to another chain.
    LendingPoolContract.CrossChainPayLoad public actionPayLoad;

    /// @notice Payload structure containing data received as a response from a cross-chain operation.
    /// @dev This holds the result returned after the cross-chain action is processed by the destination chain.
    LendingPoolContract.CrossChainResponsePayLoad public responsePayLoad;

    /// @notice Address of the LendingPoolContract authorized to interact with this contract.
    address private lendingPoolContract;

    /// @notice Stores the most recent token address used in a received message or transaction.
    address lastToken;

    /// @notice Stores the most recent amount associated with the lastToken in a received message or transaction.
    uint256 lastAmount;

    /// @notice Interface instance for accessing the Registry contract for cross-chain configuration lookups.
    IRegistry registry;

    /// @notice Interface instance of the Global State Manager used for updating or querying protocol state across chains.
    IGlobalStateManager GSM;

    /// @notice Interface instance for handling incoming CCIP messages on this contract.
    ICCIPRequestHandler ccipRequestHandler;

    /// @notice Interface instance for aggregating cross-chain state data for local use.
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

    /**
     * @notice Handles cross-chain messages received via CCIP (Chainlink Cross-Chain Interoperability Protocol).
     * @dev This function acts as the main entry point for decoding and processing incoming messages.
     *
     * The function handles different types of messages based on an identifier `id`:
     * - `id == 0`: Decodes and stores a CrossChainPayLoad struct.
     * - `id == 1`: Decodes and stores a CrossChainResponsePayLoad struct.
     *
     * It performs different logic depending on the content of the message:
     *
     * - If tokens are included in the message (`destTokenAmounts.length > 0`) and the action type is `TRANSFER`,
     *   it calls the `transferTokens()` function and emits `MessageAndTokenReceived`.
     * - If no tokens are present but this is the Ethereum chain (`block.chainid == ethChainId`), then:
     *   - If action type is `DEPOSIT_COLLATERAL`, it updates deposit details and mirrors them across chains.
     *   - If action type is `LOAN_TAKEN`, it updates loan details and mirrors them across chains.
     * - If it's another chain, it handles response payloads:
     *   - If response is `RESPONSE_COLLATERAL_INFORMATION_FOR_USER`, it updates user's collateral state.
     *   - If response is `RESPONSE_LOAN_INFORMATION_FOR_USER`, it updates user's loan state.
     *
     * @param message The incoming cross-chain message including payload data and token transfer info.
     *
     * @custom:emit Emits `MessageAndTokenReceived` when a token is received with a message.
     * @custom:emit Emits `MessageReceivedForCollateralUpdate` when a collateral update is processed on ETH chain.
     * @custom:error Only processes known payload `id` values (0 and 1); unknown IDs will silently fail.
     */

    function ccipReceiver(Client.Any2EVMMessage memory message) external {
        bytes memory rawData = message.data;
        uint64 id;
        // Extract the identifier from the message payload (first 64 bits after 32 bytes offset)
        assembly {
            id := mload(add(rawData, 32))
        }
        // Decode the message based on its type
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

        // Case 1: Message includes token transfers

        if (message.destTokenAmounts.length > 0) {
            if (
                actionPayLoad.actionType ==
                LendingPoolContract.ActionType.TRANSFER // Executes token transfer logic
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
        // Case 2: No tokens received, processing payload logic
        else if (block.chainid == ethChainId) {
            // Handle collateral deposit update on Ethereum chain
            if (
                actionPayLoad.actionType ==
                LendingPoolContract.ActionType.DEPOSIT_COLLATERAL
            ) {
                ccipRequestHandler.updateDepositCollateralDetailsOfUser(
                    actionPayLoad
                );
                // Get receiver on source chain to mirror update
                address receiver = registry.getCrossChainAddress(
                    message.sourceChainSelector,
                    "crossChainMessageReceiverAddress"
                );
                // Send mirror update for collateral
                ccipRequestHandler.updateCollateralStateMirror(
                    receiver,
                    actionPayLoad.chainId,
                    actionPayLoad.user,
                    actionPayLoad.crossChaintokenId,
                    message.sourceChainSelector
                );
                emit MessageReceivedForCollateralUpdate();
            }
            // Handle loan update on Ethereum chain
            else if (
                actionPayLoad.actionType ==
                LendingPoolContract.ActionType.LOAN_TAKEN
            ) {
                ccipRequestHandler.updateLoanDetailsOfUser(actionPayLoad);
                // Get receiver on source chain to mirror update
                address receiver = registry.getCrossChainAddress(
                    message.sourceChainSelector,
                    "crossChainMessageReceiverAddress"
                );

                // Mirror loan state to source chain

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
            }
        }
        // Case 3: Response payloads processed on non-Ethereum chains
        else {
            // Update local state with cross-chain collateral info
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
            // Update local state with cross-chain loan info
            else if (
                responsePayLoad.response ==
                LendingPoolContract.Response.RESPONSE_LOAN_INFORMATION_FOR_USER
            ) {
                LoanManager.LoanDetails memory loanInfo = abi.decode(
                    responsePayLoad.extraInformation,
                    (LoanManager.LoanDetails)
                );
                stateAggregator.updateLoanDetailsOfUser(
                    responsePayLoad.chainId,
                    responsePayLoad.user,
                    responsePayLoad.crossChainTokenId,
                    loanInfo.loanId,
                    loanInfo
                );
            } else {
                console.log("No information found");
            }
        }
    }

    /**
     * @notice Returns a sub-array (slice) of the original bytes array starting from the specified index.
     * @dev Uses inline assembly to efficiently copy memory from the `data` array into a new `result` array,
     *      starting from the `start` index to the end of the array.
     *
     * Requirements:
     * - `start` must be less than or equal to the length of the `data` array.
     *
     * Example:
     * - Given `data = 0x1234567890` (length 5), and `start = 2`, the result will be `0x7890`.
     *
     * @param data The original `bytes` array to be sliced.
     * @param start The start index (0-based) from which to begin slicing.
     * @return result The sliced `bytes` array from `start` to the end of `data`.
     */

    function sliceBytes(
        bytes memory data,
        uint256 start
    ) internal pure returns (bytes memory result) {
        require(start <= data.length, "Invalid start");
        uint256 len = data.length - start;
        assembly {
            // Allocate memory for the new result bytes array
            result := mload(0x40)
            // Allocate memory for the new result bytes array
            mstore(result, len)

            // Allocate memory for the new result bytes array

            let dataPtr := add(add(data, 32), start)
            // Pointer where we start writing in the result array
            let resultPtr := add(result, 32)

            // Pointer where we start writing in the result array
            for {
                let i := 0
            } lt(i, len) {
                i := add(i, 32)
            } {
                mstore(add(resultPtr, i), mload(add(dataPtr, i)))
            }

            // Update free memory pointer to the next clean position
            mstore(0x40, add(resultPtr, and(add(len, 31), not(31))))
        }
    }

    /**
     * @notice Transfers tokens received via cross-chain message to the lending pool contract.
     * @dev Approves the lending pool contract to transfer the specified amount of tokens,
     *      then forwards the message data to the lending pool for further processing.
     *
     * @param message The cross-chain message containing encoded data required for the transfer.
     */

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
