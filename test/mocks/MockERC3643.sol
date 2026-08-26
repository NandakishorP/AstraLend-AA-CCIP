// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC3643, IAgentRole} from "../../src/rwa/interfaces/IERC3643.sol";
import {IEligibilityRegistry} from "../../src/rwa/interfaces/IEligibilityRegistry.sol";

/**
 * @title MockERC3643
 * @notice Stands in for a third-party tokenised security — an OUSG or a BUIDL.
 *
 * @dev This is deliberately NOT part of the protocol. The whole point of the
 *      design is that the collateral is somebody else's issuance: we are a
 *      lender, not an issuer. It lives in test/mocks for the same reason
 *      MockCCIPRouter does — it substitutes for infrastructure we do not own.
 *
 *      Behaviour is copied from the T-REX reference implementation rather than
 *      invented, because the protocol has to work against the real thing:
 *
 *        - transfer requires `amount <= balance - frozenTokens`
 *        - freezePartialTokens requires `balance >= frozen + amount`
 *        - forcedTransfer unfreezes the shortfall first, then moves
 *        - all three are onlyAgent
 *        - forcedTransfer and mint still require a verified recipient
 *
 *      The identity registry is simplified to a single `isVerified` call.
 *      A real ERC-3643 also carries a compliance module, pausing and recovery,
 *      none of which the lender touches.
 */
contract MockERC3643 is ERC20, Ownable, IERC3643, IAgentRole {
    error MockERC3643__NotAgent(address caller);
    error MockERC3643__InsufficientFreeBalance(uint256 free, uint256 requested);
    error MockERC3643__FreezeExceedsBalance(uint256 balance, uint256 frozen, uint256 requested);
    error MockERC3643__UnfreezeExceedsFrozen(uint256 frozen, uint256 requested);
    error MockERC3643__RecipientNotVerified(address to);
    error MockERC3643__WalletFrozen(address wallet);

    mapping(address => uint256) private _frozenTokens;
    mapping(address => bool) private _frozenWallets;
    mapping(address => bool) private _agents;

    IEligibilityRegistry private _identityRegistry;
    uint8 private immutable _decimalsValue;

    event TokensFrozen(address indexed userAddress, uint256 amount);
    event TokensUnfrozen(address indexed userAddress, uint256 amount);
    event AddressFrozen(address indexed userAddress, bool indexed isFrozen, address indexed owner);
    event AgentAdded(address indexed agent);
    event AgentRemoved(address indexed agent);

    modifier onlyAgent() {
        if (!_agents[msg.sender]) revert MockERC3643__NotAgent(msg.sender);
        _;
    }

    constructor(string memory name_, string memory symbol_, uint8 decimals_, address issuer)
        ERC20(name_, symbol_)
        Ownable(issuer)
    {
        _decimalsValue = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimalsValue;
    }

    // ─── The rule ────────────────────────────────────────────────────────────

    /// @dev Free balance only. Mints and burns bypass it, as in the reference.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0)) {
            if (_frozenWallets[from]) revert MockERC3643__WalletFrozen(from);
            uint256 free = balanceOf(from) - _frozenTokens[from];
            if (free < value) revert MockERC3643__InsufficientFreeBalance(free, value);
        }
        if (to != address(0) && !_isVerified(to)) {
            revert MockERC3643__RecipientNotVerified(to);
        }
        super._update(from, to, value);
    }

    function _isVerified(address who) internal view returns (bool) {
        return address(_identityRegistry) == address(0) || _identityRegistry.isEligible(who);
    }

    // ─── ERC-3643 surface ────────────────────────────────────────────────────

    function getFrozenTokens(address userAddress) external view returns (uint256) {
        return _frozenTokens[userAddress];
    }

    function isFrozen(address userAddress) external view returns (bool) {
        return _frozenWallets[userAddress];
    }

    function freePartialBalanceOf(address userAddress) external view returns (uint256) {
        return balanceOf(userAddress) - _frozenTokens[userAddress];
    }

    function freezePartialTokens(address userAddress, uint256 amount) external onlyAgent {
        uint256 balance = balanceOf(userAddress);
        if (balance < _frozenTokens[userAddress] + amount) {
            revert MockERC3643__FreezeExceedsBalance(balance, _frozenTokens[userAddress], amount);
        }
        _frozenTokens[userAddress] += amount;
        emit TokensFrozen(userAddress, amount);
    }

    function unfreezePartialTokens(address userAddress, uint256 amount) external onlyAgent {
        if (_frozenTokens[userAddress] < amount) {
            revert MockERC3643__UnfreezeExceedsFrozen(_frozenTokens[userAddress], amount);
        }
        _frozenTokens[userAddress] -= amount;
        emit TokensUnfrozen(userAddress, amount);
    }

    function setAddressFrozen(address userAddress, bool freeze) external onlyAgent {
        _frozenWallets[userAddress] = freeze;
        emit AddressFrozen(userAddress, freeze, msg.sender);
    }

    /// @dev Unfreezes the shortfall before moving, exactly as T-REX does — so a
    ///      caller never has to unfreeze separately, and there is no path that
    ///      moves a frozen balance without accounting for it.
    function forcedTransfer(address from, address to, uint256 amount)
        external
        onlyAgent
        returns (bool)
    {
        if (balanceOf(from) < amount) {
            revert MockERC3643__InsufficientFreeBalance(balanceOf(from), amount);
        }
        uint256 free = balanceOf(from) - _frozenTokens[from];
        if (amount > free) {
            uint256 toUnfreeze = amount - free;
            _frozenTokens[from] -= toUnfreeze;
            emit TokensUnfrozen(from, toUnfreeze);
        }
        if (!_isVerified(to)) revert MockERC3643__RecipientNotVerified(to);
        _transfer(from, to, amount);
        return true;
    }

    // ─── Issuer surface (not the lender's business) ──────────────────────────

    function mint(address to, uint256 amount) external onlyAgent {
        _mint(to, amount);
    }

    function burn(address userAddress, uint256 amount) external onlyAgent {
        uint256 free = balanceOf(userAddress) - _frozenTokens[userAddress];
        if (free < amount) {
            uint256 toUnfreeze = amount - free;
            _frozenTokens[userAddress] -= toUnfreeze;
            emit TokensUnfrozen(userAddress, toUnfreeze);
        }
        _burn(userAddress, amount);
    }

    function setIdentityRegistry(address registry) external onlyOwner {
        _identityRegistry = IEligibilityRegistry(registry);
    }

    function identityRegistry() external view returns (address) {
        return address(_identityRegistry);
    }

    // ─── Agents ──────────────────────────────────────────────────────────────

    function addAgent(address agent) external onlyOwner {
        _agents[agent] = true;
        emit AgentAdded(agent);
    }

    function removeAgent(address agent) external onlyOwner {
        _agents[agent] = false;
        emit AgentRemoved(agent);
    }

    function isAgent(address agent) external view returns (bool) {
        return _agents[agent];
    }
}
