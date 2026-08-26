// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC3643} from "../../src/rwa/interfaces/IERC3643.sol";
import {IRWAValuation} from "../../src/rwa/interfaces/IRWAValuation.sol";

/**
 * @title MockRedemptionDesk
 * @notice Stands in for turning a foreclosed security back into cash.
 *
 * @dev Not part of the protocol, and deliberately so. Once the trustee has
 *      forced the collateral out of a defaulting borrower it holds a tokenised
 *      security, not money, and the debt is denominated in money. Closing that
 *      gap means selling into the secondary market or redeeming with the
 *      issuer — both of which happen off-chain, at a venue the lender does not
 *      operate.
 *
 *      This contract models that leg so the demo can complete. It buys tokens
 *      for stablecoin at the valuation's current price. It is honest about
 *      being a stand-in: a real deployment has the trustee sell through a
 *      broker and remit the proceeds, and no contract can make that trustless.
 *
 *      Note what it does NOT do: it does not burn. Burning someone else's
 *      security is the issuer's act, not a lender's, and we are not the issuer.
 *      It simply becomes the holder — which is why it has to be verified on the
 *      token's identity registry like anybody else.
 */
contract MockRedemptionDesk is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error RedemptionDesk__ZeroAmount();
    error RedemptionDesk__InsufficientCash(uint256 needed, uint256 available);
    error RedemptionDesk__InvalidPrice(int256 price);

    IERC3643 public immutable token;
    IERC20 public immutable stableCoin;
    IRWAValuation public immutable valuation;
    uint8 private immutable stableDecimals;
    uint8 private immutable tokenDecimals;

    event Sold(address indexed seller, uint256 tokenAmount, uint256 proceeds, uint256 priceUsed);
    event Funded(address indexed from, uint256 amount);

    constructor(
        address token_,
        address stableCoin_,
        address valuation_,
        uint8 tokenDecimals_,
        uint8 stableDecimals_
    ) {
        token = IERC3643(token_);
        stableCoin = IERC20(stableCoin_);
        valuation = IRWAValuation(valuation_);
        tokenDecimals = tokenDecimals_;
        stableDecimals = stableDecimals_;
    }

    function _price() internal view returns (uint256) {
        (, int256 answer,,,) = valuation.latestRoundData();
        if (answer <= 0) revert RedemptionDesk__InvalidPrice(answer);
        return uint256(answer);
    }

    /// @dev Multiply before dividing so small quantities survive the rounding.
    function quote(uint256 tokenAmount) public view returns (uint256) {
        uint256 price = _price();
        return (tokenAmount * price * (10 ** stableDecimals))
            / ((10 ** valuation.decimals()) * (10 ** tokenDecimals));
    }

    /**
     * @notice Sells `tokenAmount` for stablecoin at the current valuation.
     * @dev The caller must have approved the desk. Only a free balance can be
     *      sold — the token itself refuses to move a frozen one, which is what
     *      stops a borrower cashing out collateral they have pledged.
     */
    function sell(uint256 tokenAmount) external nonReentrant returns (uint256 proceeds) {
        if (tokenAmount == 0) revert RedemptionDesk__ZeroAmount();

        uint256 price = _price();
        proceeds = quote(tokenAmount);

        uint256 cash = stableCoin.balanceOf(address(this));
        if (cash < proceeds) revert RedemptionDesk__InsufficientCash(proceeds, cash);

        IERC20(address(token)).safeTransferFrom(msg.sender, address(this), tokenAmount);
        stableCoin.safeTransfer(msg.sender, proceeds);

        emit Sold(msg.sender, tokenAmount, proceeds, price);
    }

    /// @notice Where the desk's buying power comes from. Off-chain in reality.
    function fund(uint256 amount) external {
        if (amount == 0) revert RedemptionDesk__ZeroAmount();
        stableCoin.safeTransferFrom(msg.sender, address(this), amount);
        emit Funded(msg.sender, amount);
    }

    function cash() external view returns (uint256) {
        return stableCoin.balanceOf(address(this));
    }
}
