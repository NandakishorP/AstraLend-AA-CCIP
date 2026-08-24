// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ILienRegistry} from "./interfaces/ILienRegistry.sol";
import {IRWAToken} from "./interfaces/IRWAToken.sol";

/**
 * @title LienRegistry
 * @notice The public register of security interests over tokenised instruments.
 *
 * @dev `LienCreated` is not a log line about something that happened elsewhere.
 *      It *is* the register. Under the Depositories Act 1996 s.12 a pledge of
 *      dematerialised securities takes effect by being recorded, and it is the
 *      record — visible, timestamped, third-party checkable — that makes the
 *      charge good against the world. Publicity is the legal function.
 *
 *      Division of labour with the token: the registry knows which loan a
 *      charge secures and who may lift it; the token knows the running total
 *      per holder and refuses to let a pledged balance move. Neither can do the
 *      other's job, and the token's cap holds even if several registries are
 *      ever authorised against it.
 *
 *      Foreclosure is initiated by the security trustee, never by the pool. A
 *      pool is not a legal person and cannot enforce a charge; a trustee bound
 *      by the deed can. On-chain this contract only asks the token to move the
 *      balance — realising the underlying instrument happens off-chain, in the
 *      custodian's books, under the Indian Contract Act 1872 s.176 right of
 *      sale on default.
 */
contract LienRegistry is Ownable, ILienRegistry {
    error Lien__OnlyPool(address caller);
    error Lien__OnlySecurityTrustee(address caller);
    error Lien__UnknownLien(bytes32 lienId);
    error Lien__AlreadyReleased(bytes32 lienId);
    error Lien__AlreadyForeclosed(bytes32 lienId);
    error Lien__ZeroAmount();
    error Lien__ZeroAddress();
    error Lien__DuplicateLien(bytes32 lienId);
    error Lien__DecreaseExceedsLien(uint256 outstanding, uint256 requested);

    mapping(bytes32 lienId => Lien) private s_liens;
    mapping(address borrower => mapping(address token => uint256 amount)) private s_totalEncumbered;

    address private s_pool;
    address private s_securityTrustee;

    event LienCreated(
        bytes32 indexed lienId,
        address indexed borrower,
        address indexed token,
        uint256 amount,
        bytes32 loanRef,
        uint64 perfectedAt
    );
    event LienIncreased(bytes32 indexed lienId, address indexed borrower, uint256 added, uint256 total);
    event LienDecreased(bytes32 indexed lienId, address indexed borrower, uint256 removed, uint256 total);
    event LienReleased(bytes32 indexed lienId, address indexed borrower, uint256 amount, uint64 releasedAt);
    event LienForeclosed(bytes32 indexed lienId, address indexed borrower, address indexed trustee, uint256 amount);
    event PoolSet(address indexed pool);
    event SecurityTrusteeSet(address indexed trustee);

    modifier onlyPool() {
        if (msg.sender != s_pool) revert Lien__OnlyPool(msg.sender);
        _;
    }

    modifier onlySecurityTrustee() {
        if (msg.sender != s_securityTrustee) revert Lien__OnlySecurityTrustee(msg.sender);
        _;
    }

    constructor(address admin) Ownable(admin) {}

    /**
     * @notice Perfects a charge over `amount` of `token` held by `borrower`.
     * @param loanRef Opaque reference to the loan this secures. The pool owns
     *        its own loan identity scheme; the registry only needs to be able
     *        to point back at it.
     * @dev The id is derived rather than sequential so the pool can recompute
     *      it from the loan alone, without storing a second mapping.
     */
    function createLien(address borrower, address token, uint256 amount, bytes32 loanRef)
        external
        onlyPool
        returns (bytes32 lienId)
    {
        if (borrower == address(0) || token == address(0)) revert Lien__ZeroAddress();
        if (amount == 0) revert Lien__ZeroAmount();

        lienId = computeLienId(borrower, token, loanRef);
        if (s_liens[lienId].perfectedAt != 0) revert Lien__DuplicateLien(lienId);

        s_liens[lienId] = Lien({
            borrower: borrower,
            token: token,
            amount: amount,
            loanRef: loanRef,
            perfectedAt: uint64(block.timestamp),
            releasedAt: 0,
            foreclosed: false
        });
        s_totalEncumbered[borrower][token] += amount;

        // The token enforces the cap. If the borrower has already pledged this
        // holding elsewhere, this reverts and no lien is recorded.
        IRWAToken(token).encumber(borrower, amount);

        emit LienCreated(lienId, borrower, token, amount, loanRef, uint64(block.timestamp));
    }

    /**
     * @notice Adds to an existing charge.
     * @dev The pool aggregates collateral per (user, asset) rather than per
     *      loan, so a borrower topping up a position should deepen the existing
     *      charge rather than accumulate a second one. Legally this is the same
     *      pledge for a larger amount, which is what a running account charge
     *      looks like.
     */
    function increaseLien(bytes32 lienId, uint256 amount) external onlyPool {
        if (amount == 0) revert Lien__ZeroAmount();
        Lien storage lien = _activeLien(lienId);

        lien.amount += amount;
        s_totalEncumbered[lien.borrower][lien.token] += amount;

        IRWAToken(lien.token).encumber(lien.borrower, amount);

        emit LienIncreased(lienId, lien.borrower, amount, lien.amount);
    }

    /**
     * @notice Partially discharges a charge, freeing that much of the holding.
     * @dev Used when a borrower withdraws part of their collateral. Reducing to
     *      zero leaves the lien active with no amount rather than releasing it,
     *      so the register keeps a continuous record of the relationship.
     */
    function decreaseLien(bytes32 lienId, uint256 amount) external onlyPool {
        if (amount == 0) revert Lien__ZeroAmount();
        Lien storage lien = _activeLien(lienId);
        if (amount > lien.amount) revert Lien__DecreaseExceedsLien(lien.amount, amount);

        lien.amount -= amount;
        s_totalEncumbered[lien.borrower][lien.token] -= amount;

        IRWAToken(lien.token).release(lien.borrower, amount);

        emit LienDecreased(lienId, lien.borrower, amount, lien.amount);
    }

    /// @notice Lifts a charge once the debt it secures is discharged.
    function releaseLien(bytes32 lienId) external onlyPool {
        Lien storage lien = _activeLien(lienId);

        lien.releasedAt = uint64(block.timestamp);
        s_totalEncumbered[lien.borrower][lien.token] -= lien.amount;

        IRWAToken(lien.token).release(lien.borrower, lien.amount);

        emit LienReleased(lienId, lien.borrower, lien.amount, uint64(block.timestamp));
    }

    /**
     * @notice Enforces the charge, moving the pledged balance to the trustee.
     * @dev Deliberately does not check whether the loan is actually in default.
     *      The trustee is accountable for that determination under the deed,
     *      and the pool exposes the data to make it; encoding a default test
     *      here would put a contract in the position of adjudicating one.
     */
    function foreclose(bytes32 lienId) external onlySecurityTrustee {
        Lien storage lien = _activeLien(lienId);

        lien.foreclosed = true;
        lien.releasedAt = uint64(block.timestamp);
        s_totalEncumbered[lien.borrower][lien.token] -= lien.amount;

        IRWAToken(lien.token).forcedTransfer(lien.borrower, msg.sender, lien.amount, lienId);

        emit LienForeclosed(lienId, lien.borrower, msg.sender, lien.amount);
    }

    function _activeLien(bytes32 lienId) private view returns (Lien storage lien) {
        lien = s_liens[lienId];
        if (lien.perfectedAt == 0) revert Lien__UnknownLien(lienId);
        if (lien.foreclosed) revert Lien__AlreadyForeclosed(lienId);
        if (lien.releasedAt != 0) revert Lien__AlreadyReleased(lienId);
    }

    function computeLienId(address borrower, address token, bytes32 loanRef) public pure returns (bytes32) {
        return keccak256(abi.encode(borrower, token, loanRef));
    }

    function getLien(bytes32 lienId) external view returns (Lien memory) {
        return s_liens[lienId];
    }

    function isActive(bytes32 lienId) external view returns (bool) {
        Lien memory lien = s_liens[lienId];
        return lien.perfectedAt != 0 && lien.releasedAt == 0 && !lien.foreclosed;
    }

    function totalEncumberedBy(address borrower, address token) external view returns (uint256) {
        return s_totalEncumbered[borrower][token];
    }

    function setPool(address pool) external onlyOwner {
        if (pool == address(0)) revert Lien__ZeroAddress();
        s_pool = pool;
        emit PoolSet(pool);
    }

    function setSecurityTrustee(address trustee) external onlyOwner {
        if (trustee == address(0)) revert Lien__ZeroAddress();
        s_securityTrustee = trustee;
        emit SecurityTrusteeSet(trustee);
    }

    function getPool() external view returns (address) {
        return s_pool;
    }

    function getSecurityTrustee() external view returns (address) {
        return s_securityTrustee;
    }
}
