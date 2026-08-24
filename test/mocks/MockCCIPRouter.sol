// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

/**
 * @title MockCCIPRouter
 * @notice Stands in for the Chainlink CCIP Router on a local node.
 *
 * On Ethereum and Arbitrum the real Router accepts a message, charges a fee, and
 * hands off to Chainlink's DON, which delivers it to the destination chain. None
 * of that exists on a bare Anvil node, so this mock does the source-side half —
 * charge a fee, assign a message id, emit everything a delivery agent needs —
 * and the off-chain relayer in `tooling/relayer.ts` does the destination half by
 * calling `ccipReceive` on the destination chain as this contract's counterpart.
 *
 * This is a local-development and demo aid only. It is never deployed to a real
 * network: the deploy scripts only use it when `useMockRouter` is set, and the
 * integration tests exercise the protocol against genuine forked CCIP contracts
 * instead.
 *
 * @dev Token transfers are intentionally not simulated. Every message the
 *      protocol sends today is data-only; attaching tokens would require
 *      simulating lock/mint token pools on both sides, which the demo does not
 *      need. A message carrying tokens reverts rather than silently dropping
 *      them.
 */
contract MockCCIPRouter is IRouterClient {
    /// @notice Flat fee charged per message, in native token.
    uint256 public fee = 0.0005 ether;

    /// @notice Incrementing source of message-id entropy.
    uint256 private s_nonce;

    error MockCCIPRouter__InsufficientFee(uint256 supplied, uint256 required);
    error MockCCIPRouter__TokenTransfersNotSupported();

    /**
     * @notice Emitted for every accepted message. The relayer watches this.
     *
     * @param messageId                 Unique id, mirrors CCIP's messageId
     * @param destinationChainSelector  CCIP selector of the destination chain
     * @param sender                    Contract that called `ccipSend`
     * @param receiver                  Decoded destination receiver address
     * @param data                      Opaque payload for the destination
     * @param feePaid                   Native token taken as the fee
     */
    event MockCCIPMessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address indexed sender,
        address receiver,
        bytes data,
        uint256 feePaid
    );

    /// @notice Every chain is routable; the relayer decides what it can deliver.
    function isChainSupported(uint64) external pure returns (bool supported) {
        return true;
    }

    /// @inheritdoc IRouterClient
    function getFee(uint64, Client.EVM2AnyMessage memory) external view returns (uint256) {
        return fee;
    }

    /// @notice Lets a demo script make fees free, or make them expensive.
    function setFee(uint256 newFee) external {
        fee = newFee;
    }

    /// @inheritdoc IRouterClient
    function ccipSend(
        uint64 destinationChainSelector,
        Client.EVM2AnyMessage calldata message
    ) external payable returns (bytes32 messageId) {
        if (message.tokenAmounts.length > 0) {
            revert MockCCIPRouter__TokenTransfersNotSupported();
        }
        if (msg.value < fee) {
            revert MockCCIPRouter__InsufficientFee(msg.value, fee);
        }

        messageId = keccak256(
            abi.encode(block.chainid, destinationChainSelector, msg.sender, s_nonce++, block.timestamp)
        );

        emit MockCCIPMessageSent(
            messageId,
            destinationChainSelector,
            msg.sender,
            abi.decode(message.receiver, (address)),
            message.data,
            msg.value
        );
    }

    receive() external payable {}
}
