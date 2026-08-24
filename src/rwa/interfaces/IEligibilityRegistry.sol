// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IEligibilityRegistry
 * @notice Answers the only question the token needs to ask before it lets an
 *         address hold a restricted instrument: may this person hold it?
 * @dev Deliberately one function. How eligibility is established — an operator
 *      allowlist today, a zero-knowledge credential proof later — is the
 *      registry's business, not the token's.
 */
interface IEligibilityRegistry {
    function isEligible(address subject) external view returns (bool);
}
