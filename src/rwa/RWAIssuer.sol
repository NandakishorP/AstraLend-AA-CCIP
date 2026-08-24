// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {RWAToken} from "./RWAToken.sol";
import {IRWAValuation} from "./interfaces/IRWAValuation.sol";

/**
 * @title RWAIssuer
 * @notice The SPV's on-chain face: mints the tokenised interest against a real
 *         holding, and redeems it for cash at net asset value.
 *
 * @dev Redemption is what makes enforcement self-executing. Once the trustee
 *      holds a foreclosed balance it does not need a court, a buyer or an
 *      auction — the instrument liquidates itself at a value nobody has to
 *      agree on, because for a bill the value is arithmetic.
 *
 *      The reserve is the honest part of the model. Redeeming on-chain requires
 *      stablecoin to be present, and in a real deployment it arrives because
 *      the custodian sold or redeemed the underlying and remitted the proceeds.
 *      That leg is off-chain and cannot be made trustless — the SPV's
 *      obligation to fund it is a term of the trust deed, not a line of code.
 *      `fundReserve` is where that obligation lands.
 *
 *      Minting is not permissionless and should not be. Each unit must
 *      correspond to a real holding in the custodian's account, which is a fact
 *      about the world that only the SPV can assert.
 */
contract RWAIssuer is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error RWAIssuer__ZeroAmount();
    error RWAIssuer__ZeroAddress();
    error RWAIssuer__InsufficientReserve(uint256 needed, uint256 available);
    error RWAIssuer__NotFreeBalance(uint256 free, uint256 requested);
    error RWAIssuer__InvalidNav(int256 nav);

    RWAToken private immutable i_token;
    IERC20 private immutable i_stableCoin;
    IRWAValuation private s_valuation;

    /// @dev Stablecoin decimals differ from the instrument's, so the conversion
    ///      has to be explicit rather than assumed.
    uint8 private immutable i_stableDecimals;

    event Minted(address indexed to, uint256 amount);
    event Redeemed(address indexed from, uint256 tokenAmount, uint256 stableAmount, uint256 navUsed);
    event ReserveFunded(address indexed from, uint256 amount);
    event ReserveWithdrawn(address indexed to, uint256 amount);
    event ValuationSet(address indexed valuation);

    constructor(address token, address stableCoin, uint8 stableDecimals, address admin) Ownable(admin) {
        if (token == address(0) || stableCoin == address(0)) revert RWAIssuer__ZeroAddress();
        i_token = RWAToken(token);
        i_stableCoin = IERC20(stableCoin);
        i_stableDecimals = stableDecimals;
    }

    /// @notice Issues tokenised interest against a holding the custodian has.
    function mint(address to, uint256 amount) external onlyOwner {
        if (amount == 0) revert RWAIssuer__ZeroAmount();
        i_token.mint(to, amount);
        emit Minted(to, amount);
    }

    /**
     * @notice Burns `tokenAmount` and pays out its current value in stablecoin.
     * @dev Only a free balance can be redeemed. An encumbered holding would
     *      otherwise be convertible to cash by its own pledgor, which is
     *      precisely the leakage the charge exists to prevent. The token's
     *      `_update` would catch this on burn anyway; checking here turns an
     *      opaque revert into a named one.
     */
    function redeem(uint256 tokenAmount) external nonReentrant returns (uint256 stableAmount) {
        if (tokenAmount == 0) revert RWAIssuer__ZeroAmount();

        uint256 free = i_token.freeBalanceOf(msg.sender);
        if (free < tokenAmount) revert RWAIssuer__NotFreeBalance(free, tokenAmount);

        uint256 nav = _currentNav();
        stableAmount = _toStable(tokenAmount, nav);

        uint256 reserve = i_stableCoin.balanceOf(address(this));
        if (reserve < stableAmount) revert RWAIssuer__InsufficientReserve(stableAmount, reserve);

        i_token.burn(msg.sender, tokenAmount);
        i_stableCoin.safeTransfer(msg.sender, stableAmount);

        emit Redeemed(msg.sender, tokenAmount, stableAmount, nav);
    }

    /**
     * @dev NAV carries 8 decimals (Chainlink convention) and is quoted per whole
     *      token, so the conversion is:
     *
     *        stable = tokenAmount * nav / 10^navDecimals
     *                              * 10^stableDecimals / 10^tokenDecimals
     *
     *      Ordered to multiply before dividing so precision is not lost on the
     *      way through.
     */
    function _toStable(uint256 tokenAmount, uint256 nav) internal view returns (uint256) {
        uint8 navDecimals = s_valuation.decimals();
        uint256 numerator = tokenAmount * nav * (10 ** i_stableDecimals);
        uint256 denominator = (10 ** navDecimals) * (10 ** i_token.decimals());
        return numerator / denominator;
    }

    function _currentNav() internal view returns (uint256) {
        (, int256 answer,,,) = s_valuation.latestRoundData();
        if (answer <= 0) revert RWAIssuer__InvalidNav(answer);
        return uint256(answer);
    }

    function quoteRedemption(uint256 tokenAmount) external view returns (uint256) {
        return _toStable(tokenAmount, _currentNav());
    }

    /// @notice Where the custodian's remittance of realised proceeds lands.
    function fundReserve(uint256 amount) external {
        if (amount == 0) revert RWAIssuer__ZeroAmount();
        i_stableCoin.safeTransferFrom(msg.sender, address(this), amount);
        emit ReserveFunded(msg.sender, amount);
    }

    function withdrawReserve(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert RWAIssuer__ZeroAddress();
        i_stableCoin.safeTransfer(to, amount);
        emit ReserveWithdrawn(to, amount);
    }

    function setValuation(address valuation) external onlyOwner {
        if (valuation == address(0)) revert RWAIssuer__ZeroAddress();
        s_valuation = IRWAValuation(valuation);
        emit ValuationSet(valuation);
    }

    function getToken() external view returns (address) {
        return address(i_token);
    }

    function getStableCoin() external view returns (address) {
        return address(i_stableCoin);
    }

    function getValuation() external view returns (address) {
        return address(s_valuation);
    }

    function getReserve() external view returns (uint256) {
        return i_stableCoin.balanceOf(address(this));
    }

    function nav() external view returns (uint256) {
        return _currentNav();
    }
}
