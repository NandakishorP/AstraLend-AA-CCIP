// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IERC3643
 * @notice The subset of ERC-3643 (T-REX) that this protocol depends on.
 *
 * @dev We do not issue the collateral. Real tokenised securities — Ondo,
 *      Tokeny-issued instruments, most permissioned RWA — are ERC-3643, and
 *      that standard already carries the primitive this design needs:
 *
 *        balance − frozenTokens = free balance
 *
 *      A conforming `transfer` requires the sender to hold enough *free*
 *      balance, so freezing a portion pledges it in place without moving it.
 *      That is the entire encumbrance model, and it is somebody else's
 *      contract, already deployed, already audited.
 *
 *      Only the functions the protocol actually calls are declared. A full
 *      ERC-3643 token also carries an identity registry, a compliance module,
 *      mint/burn and pausing; none of that is the lender's business.
 *
 *      Every mutating function here is `onlyAgent` on the token. The protocol's
 *      LienRegistry therefore has to be appointed as an agent by the issuer —
 *      which is a business relationship, not a line of code, and is the real
 *      integration dependency of this design. On-chain it is `addAgent`; on
 *      paper it is the tri-party agreement.
 */
interface IERC3643 is IERC20 {
    /// @notice Tokens frozen in place. `balanceOf - getFrozenTokens` is spendable.
    function getFrozenTokens(address userAddress) external view returns (uint256);

    /// @notice Whether the whole wallet is frozen, independent of any amount.
    function isFrozen(address userAddress) external view returns (bool);

    /**
     * @notice Freezes `amount` of `userAddress`'s balance in place.
     * @dev onlyAgent. Reverts unless `balance >= frozen + amount`, which is what
     *      makes the same holding unable to back two loans — every agent
     *      increments the same counter, so total freezes can never exceed the
     *      balance.
     */
    function freezePartialTokens(address userAddress, uint256 amount) external;

    /// @notice Releases `amount` of frozen balance. onlyAgent.
    function unfreezePartialTokens(address userAddress, uint256 amount) external;

    /**
     * @notice Moves tokens on enforcement, bypassing compliance rules.
     * @dev onlyAgent. The reference implementation unfreezes only the
     *      *shortfall*: if `amount` exceeds the free balance, the difference is
     *      unfrozen and `TokensUnfrozen` emitted. So it spends free tokens
     *      first and dips into frozen for the rest.
     *
     *      That is not what a foreclosure wants. Taking a charge of 800 from a
     *      holder with 200 free would consume the 200 free tokens plus 600
     *      pledged ones and leave 200 frozen against a lien that no longer
     *      exists. The registry therefore unfreezes the exact charge before
     *      calling this, so the transfer takes precisely what was pledged.
     *
     *      The recipient must still be verified on the token's identity
     *      registry. A security cannot be forced into an ineligible wallet even
     *      by enforcement, so the security trustee has to be onboarded like any
     *      other holder.
     */
    function forcedTransfer(address from, address to, uint256 amount) external returns (bool);
}

/**
 * @title IAgentRole
 * @notice Agent management, as ERC-3643 incorporates it.
 * @dev The protocol only ever *reads* this — `isAgent` is how a deployment
 *      checks it has actually been granted the rights it needs, rather than
 *      discovering the omission at the first foreclosure.
 */
interface IAgentRole {
    function addAgent(address agent) external;

    function removeAgent(address agent) external;

    function isAgent(address agent) external view returns (bool);
}
