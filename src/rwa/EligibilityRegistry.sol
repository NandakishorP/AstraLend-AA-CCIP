// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IEligibilityRegistry} from "./interfaces/IEligibilityRegistry.sol";

/**
 * @title EligibilityRegistry
 * @notice Records who may hold a restricted instrument, and until when.
 *
 * @dev Holder restriction is not optional for a security. Someone has to answer
 *      "may this address hold this?" and the answer has to be enforceable at
 *      transfer time, which is why RWAToken consults this on every `_update`.
 *
 *      Eligibility is granted by an operator here — the SPV or its compliance
 *      agent attesting that it has done the KYC. That is how the market works
 *      today and it is honest about the trust involved.
 *
 *      `_register` is deliberately internal so a credential verifier can later
 *      grant eligibility from a zero-knowledge proof without this contract or
 *      the token changing. The seam exists; nothing is built on it yet.
 *
 *      Expiry matters because eligibility decays. Accreditation lapses,
 *      sanctions lists change, and a permanent flag would outlive the diligence
 *      behind it.
 */
contract EligibilityRegistry is Ownable, IEligibilityRegistry {
    error Eligibility__NotAnOperator(address caller);
    error Eligibility__ExpiryInPast(uint64 expiry, uint256 nowTs);
    error Eligibility__ZeroAddress();

    struct Status {
        bool eligible;
        uint64 expiry;
        bytes32 jurisdiction;
        uint64 registeredAt;
    }

    mapping(address subject => Status) private s_status;
    mapping(address operator => bool) private s_operators;

    event EligibilityGranted(address indexed subject, bytes32 indexed jurisdiction, uint64 expiry);
    event EligibilityRevoked(address indexed subject);
    event OperatorSet(address indexed operator, bool allowed);

    modifier onlyOperator() {
        if (!s_operators[msg.sender] && msg.sender != owner()) {
            revert Eligibility__NotAnOperator(msg.sender);
        }
        _;
    }

    constructor(address admin) Ownable(admin) {}

    /**
     * @notice Attests that `subject` may hold the instrument until `expiry`.
     * @param jurisdiction e.g. bytes32("IN") or bytes32("IFSC") — recorded so a
     *        transfer restriction can later be made jurisdiction-aware without
     *        re-onboarding anyone.
     */
    function grantEligibility(address subject, bytes32 jurisdiction, uint64 expiry) external onlyOperator {
        if (subject == address(0)) revert Eligibility__ZeroAddress();
        if (expiry <= block.timestamp) revert Eligibility__ExpiryInPast(expiry, block.timestamp);

        s_status[subject] =
            Status({eligible: true, expiry: expiry, jurisdiction: jurisdiction, registeredAt: uint64(block.timestamp)});

        emit EligibilityGranted(subject, jurisdiction, expiry);
    }

    function revokeEligibility(address subject) external onlyOperator {
        delete s_status[subject];
        emit EligibilityRevoked(subject);
    }

    /// @dev An expired attestation is not eligible, without anyone having to
    ///      run a revocation transaction to make that true.
    function isEligible(address subject) external view returns (bool) {
        Status memory status = s_status[subject];
        return status.eligible && status.expiry > block.timestamp;
    }

    function getStatus(address subject) external view returns (Status memory) {
        return s_status[subject];
    }

    function setOperator(address operator, bool allowed) external onlyOwner {
        s_operators[operator] = allowed;
        emit OperatorSet(operator, allowed);
    }

    function isOperator(address operator) external view returns (bool) {
        return s_operators[operator];
    }
}
