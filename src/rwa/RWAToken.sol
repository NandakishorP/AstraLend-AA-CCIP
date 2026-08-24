// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IEligibilityRegistry} from "./interfaces/IEligibilityRegistry.sol";

/**
 * @title RWAToken
 * @notice A tokenised beneficial interest in a real-world instrument, which can
 *         be pledged without being transferred.
 *
 * @dev This contract is the whole thesis in about a hundred lines.
 *
 *      Conventional DeFi lending takes custody: the borrower transfers tokens
 *      to a pool, and the pool holds them. For a regulated instrument that is
 *      fatal, because the pool becomes holder of record and inherits custody
 *      licensing, eligibility rules and transfer-agent obligations that a
 *      contract cannot discharge. It is why every RWA lending venue today runs
 *      through a licensed custodian.
 *
 *      Secured credit never worked that way. A mortgage does not transfer the
 *      house; it creates a charge over it. Indian law says the same thing for
 *      dematerialised securities — under the Depositories Act 1996 s.12 a
 *      pledge is *recorded* while the security stays in the pledgor's own
 *      account. SEBI made that mandatory for broker margin in September 2020,
 *      specifically to stop the custody-transfer abuse that the Karvy episode
 *      exposed.
 *
 *      So: the balance stays put and a second number moves.
 *
 *          balanceOf(alice)     100,000  <- never changes when pledging
 *          encumberedOf(alice)   80,000  <- the charge
 *          freeBalanceOf(alice)  20,000  <- what she can still move
 *
 *      Enforcement lives in `_update`, which in OpenZeppelin v5 is the sole
 *      mutator of `_balances` — `_transfer`, `_mint` and `_burn` all route
 *      through it and nothing else touches the ledger. Overriding it once
 *      leaves no second path to find, whether the caller is a wallet, a DEX
 *      router, an aggregator or a contract nobody has written yet.
 *
 *      Four roles, each with exactly one job, mirroring the legal parties:
 *
 *        owner            SPV administrator; wires the other three
 *        issuer           mints and burns against the underlying holding
 *        lienRegistry     the only caller that may encumber or release
 *        securityTrustee  the only caller that may move a pledged balance
 *
 *      The trustee is the debenture-trustee analogue (SEBI (Debenture Trustees)
 *      Regulations 1993): a pool of dispersed lenders cannot each hold a
 *      security interest, so a legally capable person holds it for them.
 */
contract RWAToken is ERC20, Ownable {
    error RWAToken__Encumbered(uint256 free, uint256 requested);
    error RWAToken__OverEncumbered(uint256 balance, uint256 alreadyEncumbered, uint256 requested);
    error RWAToken__ReleaseExceedsEncumbrance(uint256 encumbered, uint256 requested);
    error RWAToken__RecipientNotEligible(address to);
    error RWAToken__OnlyLienRegistry(address caller);
    error RWAToken__OnlyEnforcementAgent(address caller);
    error RWAToken__OnlyIssuer(address caller);
    error RWAToken__ZeroAddress();

    /// @notice The charge standing against each holder's balance.
    mapping(address holder => uint256 amount) private s_encumbered;

    address private s_lienRegistry;
    address private s_enforcementAgent;
    address private s_issuer;
    IEligibilityRegistry private s_eligibility;

    uint8 private immutable i_decimals;

    /**
     * @notice keccak256 of the trust deed governing this instrument.
     * @dev The token is a beneficial interest under a private trust (Indian
     *      Trusts Act 1882), not the security itself. That framing is what lets
     *      the structure stand without a tokenisation statute: settled trust and
     *      contract law carry it. Anchoring the deed's hash on-chain is what
     *      binds the two records together.
     */
    bytes32 private s_trustDeedHash;
    string private s_trustDeedURI;

    event Encumbered(address indexed holder, uint256 amount, uint256 total);
    event Released(address indexed holder, uint256 amount, uint256 total);
    event ForcedTransfer(address indexed from, address indexed to, uint256 amount, bytes32 indexed lienId);
    event LienRegistrySet(address indexed registry);
    event EnforcementAgentSet(address indexed agent);
    event IssuerSet(address indexed issuer);
    event EligibilityRegistrySet(address indexed registry);
    event TrustDeedSet(bytes32 indexed deedHash, string uri);

    modifier onlyLienRegistry() {
        if (msg.sender != s_lienRegistry) revert RWAToken__OnlyLienRegistry(msg.sender);
        _;
    }

    modifier onlyEnforcementAgent() {
        if (msg.sender != s_enforcementAgent) revert RWAToken__OnlyEnforcementAgent(msg.sender);
        _;
    }

    modifier onlyIssuer() {
        if (msg.sender != s_issuer) revert RWAToken__OnlyIssuer(msg.sender);
        _;
    }

    constructor(string memory name_, string memory symbol_, uint8 decimals_, address admin)
        ERC20(name_, symbol_)
        Ownable(admin)
    {
        i_decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return i_decimals;
    }

    // ─── The rule ────────────────────────────────────────────────────────────

    /**
     * @dev Two conditions express the entire legal model:
     *      a pledge cannot be spent, and only eligible persons may hold.
     *
     *      Mints (from == 0) skip the encumbrance check because there is no
     *      balance to charge against. Burns (to == 0) skip the eligibility
     *      check because the zero address holds nothing.
     */
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0)) {
            uint256 free = balanceOf(from) - s_encumbered[from];
            if (free < value) revert RWAToken__Encumbered(free, value);
        }

        if (to != address(0) && address(s_eligibility) != address(0)) {
            if (!s_eligibility.isEligible(to)) revert RWAToken__RecipientNotEligible(to);
        }

        super._update(from, to, value);
    }

    // ─── Views ───────────────────────────────────────────────────────────────

    function encumberedOf(address holder) public view returns (uint256) {
        return s_encumbered[holder];
    }

    function freeBalanceOf(address holder) public view returns (uint256) {
        return balanceOf(holder) - s_encumbered[holder];
    }

    // ─── Charge lifecycle ────────────────────────────────────────────────────

    /**
     * @notice Records a charge against `holder`'s balance.
     * @dev The cap here is what prevents the same holding backing two loans.
     *      Because every lien registry increments this one counter, total
     *      encumbrance across all lenders can never exceed what the holder
     *      actually owns — the token is the register of record, not any
     *      individual lending protocol.
     */
    function encumber(address holder, uint256 amount) external onlyLienRegistry {
        uint256 already = s_encumbered[holder];
        uint256 updated = already + amount;
        if (updated > balanceOf(holder)) {
            revert RWAToken__OverEncumbered(balanceOf(holder), already, amount);
        }
        s_encumbered[holder] = updated;
        emit Encumbered(holder, amount, updated);
    }

    function release(address holder, uint256 amount) external onlyLienRegistry {
        uint256 already = s_encumbered[holder];
        if (amount > already) revert RWAToken__ReleaseExceedsEncumbrance(already, amount);
        uint256 updated = already - amount;
        s_encumbered[holder] = updated;
        emit Released(holder, amount, updated);
    }

    /**
     * @notice Moves a pledged balance on enforcement of the security.
     * @dev The one path allowed through the rule above, and it does not bypass
     *      it — the charge is discharged first, so by the time `_transfer`
     *      reaches `_update` the balance is genuinely free. Same check, no
     *      exception carved into it.
     *
     *      Restricting this to the enforcement agent is what keeps the
     *      structure legally coherent. The agent is the LienRegistry, which
     *      only acts on the security trustee's instruction against a recorded
     *      lien — so a balance can never move without both a legal person
     *      deciding and a register entry justifying it. Its off-chain counterpart is
     *      the pawnee's right of sale on default under the Indian Contract Act
     *      1872 s.176.
     */
    function forcedTransfer(address from, address to, uint256 amount, bytes32 lienId)
        external
        onlyEnforcementAgent
    {
        uint256 charged = s_encumbered[from];
        uint256 discharged = amount > charged ? charged : amount;
        if (discharged != 0) {
            uint256 remaining = charged - discharged;
            s_encumbered[from] = remaining;
            emit Released(from, discharged, remaining);
        }
        _transfer(from, to, amount);
        emit ForcedTransfer(from, to, amount, lienId);
    }

    // ─── Supply, controlled by the issuer ────────────────────────────────────

    function mint(address to, uint256 amount) external onlyIssuer {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyIssuer {
        _burn(from, amount);
    }

    // ─── Wiring ──────────────────────────────────────────────────────────────

    function setLienRegistry(address registry) external onlyOwner {
        if (registry == address(0)) revert RWAToken__ZeroAddress();
        s_lienRegistry = registry;
        emit LienRegistrySet(registry);
    }

    /**
     * @notice The contract permitted to move a pledged balance on enforcement.
     * @dev This is the LienRegistry, not the trustee's own address. The registry
     *      holds the lien records and gates foreclosure behind the security
     *      trustee, so the legal person stays the one who decides while the
     *      contract is the one that executes. Pointing this at an EOA would let
     *      a pledged balance move with no lien record to justify it.
     */
    function setEnforcementAgent(address agent) external onlyOwner {
        if (agent == address(0)) revert RWAToken__ZeroAddress();
        s_enforcementAgent = agent;
        emit EnforcementAgentSet(agent);
    }

    function setIssuer(address issuer) external onlyOwner {
        if (issuer == address(0)) revert RWAToken__ZeroAddress();
        s_issuer = issuer;
        emit IssuerSet(issuer);
    }

    /// @dev Leaving this unset disables the holder restriction, which is only
    ///      appropriate for a test fixture.
    function setEligibilityRegistry(address registry) external onlyOwner {
        s_eligibility = IEligibilityRegistry(registry);
        emit EligibilityRegistrySet(registry);
    }

    function setTrustDeed(bytes32 deedHash, string calldata uri) external onlyOwner {
        s_trustDeedHash = deedHash;
        s_trustDeedURI = uri;
        emit TrustDeedSet(deedHash, uri);
    }

    function getLienRegistry() external view returns (address) {
        return s_lienRegistry;
    }

    function getEnforcementAgent() external view returns (address) {
        return s_enforcementAgent;
    }

    function getIssuer() external view returns (address) {
        return s_issuer;
    }

    function getEligibilityRegistry() external view returns (address) {
        return address(s_eligibility);
    }

    function getTrustDeed() external view returns (bytes32, string memory) {
        return (s_trustDeedHash, s_trustDeedURI);
    }
}
