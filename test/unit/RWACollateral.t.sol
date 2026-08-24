// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RWAToken} from "../../src/rwa/RWAToken.sol";
import {RWAIssuer} from "../../src/rwa/RWAIssuer.sol";
import {LienRegistry} from "../../src/rwa/LienRegistry.sol";
import {EligibilityRegistry} from "../../src/rwa/EligibilityRegistry.sol";
import {TBillNavOracle} from "../../src/rwa/TBillNavOracle.sol";
import {StableCoin} from "../../src/tokens/StableCoin.sol";
import {ILienRegistry} from "../../src/rwa/interfaces/ILienRegistry.sol";

/**
 * Exercises the encumbrance model end to end.
 *
 * The claim under test is narrow and worth stating: a pledged balance stays in
 * the borrower's wallet, cannot be moved by anyone including the borrower, and
 * cannot be pledged a second time — and on default a single authorised party
 * can realise it without the borrower's cooperation.
 */
contract RWACollateralTest is Test {
    RWAToken internal token;
    RWAIssuer internal issuer;
    LienRegistry internal liens;
    EligibilityRegistry internal eligibility;
    TBillNavOracle internal nav;
    StableCoin internal stable;

    address internal admin = makeAddr("spvAdmin");
    address internal trustee = makeAddr("securityTrustee");
    address internal pool = makeAddr("lendingPool");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal outsider = makeAddr("ineligibleExchange");

    // A 91-day bill: bought at 98.75, redeems at 100. Chainlink-style 8dp.
    uint256 internal constant ISSUE_PRICE = 98_75000000;
    uint256 internal constant FACE_VALUE = 100_00000000;
    uint64 internal issueDate;
    uint64 internal maturityDate;

    uint256 internal constant ALICE_HOLDING = 1_000e18;
    bytes32 internal constant LOAN_REF = keccak256("loan-42");

    function setUp() public {
        issueDate = uint64(block.timestamp);
        maturityDate = uint64(block.timestamp + 91 days);

        stable = new StableCoin();
        nav = new TBillNavOracle("91-day T-Bill", ISSUE_PRICE, FACE_VALUE, issueDate, maturityDate);

        vm.startPrank(admin);
        eligibility = new EligibilityRegistry(admin);
        token = new RWAToken("Treasury Bill 91D", "TBILL", 18, admin);
        liens = new LienRegistry(admin);
        issuer = new RWAIssuer(address(token), address(stable), 18, admin);

        token.setLienRegistry(address(liens));
        token.setEnforcementAgent(address(liens));
        token.setIssuer(address(issuer));
        token.setEligibilityRegistry(address(eligibility));
        token.setTrustDeed(keccak256("trust-deed-v1"), "ipfs://trust-deed");

        liens.setPool(pool);
        liens.setSecurityTrustee(trustee);
        issuer.setValuation(address(nav));

        // Everyone who may hold the instrument, and nobody else.
        eligibility.grantEligibility(alice, bytes32("IN"), uint64(block.timestamp + 365 days));
        eligibility.grantEligibility(bob, bytes32("IN"), uint64(block.timestamp + 365 days));
        eligibility.grantEligibility(trustee, bytes32("IN"), uint64(block.timestamp + 365 days));

        issuer.mint(alice, ALICE_HOLDING);
        vm.stopPrank();
    }

    // ─── The core rule ───────────────────────────────────────────────────────

    function test_freeBalanceTransfersNormally() public {
        vm.prank(alice);
        token.transfer(bob, 100e18);

        assertEq(token.balanceOf(bob), 100e18);
        assertEq(token.balanceOf(alice), ALICE_HOLDING - 100e18);
    }

    function test_encumberedBalanceCannotBeTransferred() public {
        _pledge(800e18);

        // Balance is untouched — the tokens never left her wallet.
        assertEq(token.balanceOf(alice), ALICE_HOLDING);
        assertEq(token.encumberedOf(alice), 800e18);
        assertEq(token.freeBalanceOf(alice), 200e18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RWAToken.RWAToken__Encumbered.selector, 200e18, 900e18));
        token.transfer(bob, 900e18);
    }

    function test_freeRemainderStillMovesWhilePledged() public {
        _pledge(800e18);

        vm.prank(alice);
        token.transfer(bob, 200e18);

        assertEq(token.balanceOf(bob), 200e18);
        assertEq(token.freeBalanceOf(alice), 0);
    }

    /// A custodial protocol pulling collateral in is the ordinary DeFi deposit
    /// path. It must fail against a pledged balance, or the same holding could
    /// back a loan here and a loan there.
    function test_anotherProtocolCannotPullPledgedTokens() public {
        _pledge(800e18);

        address rivalPool = makeAddr("rivalPool");
        vm.prank(admin);
        eligibility.grantEligibility(rivalPool, bytes32("IN"), uint64(block.timestamp + 365 days));

        vm.prank(alice);
        token.approve(rivalPool, ALICE_HOLDING);

        vm.prank(rivalPool);
        vm.expectRevert(abi.encodeWithSelector(RWAToken.RWAToken__Encumbered.selector, 200e18, 800e18));
        token.transferFrom(alice, rivalPool, 800e18);
    }

    // ─── Double-pledge prevention ────────────────────────────────────────────

    function test_cannotEncumberBeyondBalance() public {
        _pledge(800e18);

        vm.prank(pool);
        vm.expectRevert(
            abi.encodeWithSelector(RWAToken.RWAToken__OverEncumbered.selector, ALICE_HOLDING, 800e18, 300e18)
        );
        liens.createLien(alice, address(token), 300e18, keccak256("loan-43"));
    }

    function test_secondLienAllowedAgainstFreeRemainder() public {
        _pledge(800e18);

        vm.prank(pool);
        liens.createLien(alice, address(token), 200e18, keccak256("loan-43"));

        assertEq(token.encumberedOf(alice), ALICE_HOLDING);
        assertEq(token.freeBalanceOf(alice), 0);
    }

    function test_duplicateLienForSameLoanReverts() public {
        _pledge(800e18);
        bytes32 lienId = liens.computeLienId(alice, address(token), LOAN_REF);

        vm.prank(pool);
        vm.expectRevert(abi.encodeWithSelector(LienRegistry.Lien__DuplicateLien.selector, lienId));
        liens.createLien(alice, address(token), 100e18, LOAN_REF);
    }

    // ─── Running-account charge ──────────────────────────────────────────────

    /// The pool aggregates collateral per (user, asset), so topping up must
    /// deepen the existing charge rather than open a second one.
    function test_increaseLienDeepensTheSameCharge() public {
        bytes32 lienId = _pledge(500e18);

        vm.prank(pool);
        liens.increaseLien(lienId, 300e18);

        assertEq(token.encumberedOf(alice), 800e18);
        assertEq(token.freeBalanceOf(alice), 200e18);
        assertEq(liens.getLien(lienId).amount, 800e18);
        assertEq(liens.totalEncumberedBy(alice, address(token)), 800e18);
    }

    function test_decreaseLienFreesCollateral() public {
        bytes32 lienId = _pledge(800e18);

        vm.prank(pool);
        liens.decreaseLien(lienId, 300e18);

        assertEq(token.encumberedOf(alice), 500e18);
        assertEq(token.freeBalanceOf(alice), 500e18);

        vm.prank(alice);
        token.transfer(bob, 500e18);
        assertEq(token.balanceOf(bob), 500e18);
    }

    function test_cannotDecreaseBeyondTheCharge() public {
        bytes32 lienId = _pledge(500e18);

        vm.prank(pool);
        vm.expectRevert(abi.encodeWithSelector(LienRegistry.Lien__DecreaseExceedsLien.selector, 500e18, 600e18));
        liens.decreaseLien(lienId, 600e18);
    }

    function test_increaseCannotExceedHolding() public {
        bytes32 lienId = _pledge(800e18);

        vm.prank(pool);
        vm.expectRevert(
            abi.encodeWithSelector(RWAToken.RWAToken__OverEncumbered.selector, ALICE_HOLDING, 800e18, 300e18)
        );
        liens.increaseLien(lienId, 300e18);
    }

    // ─── Access control on the charge ────────────────────────────────────────

    function test_onlyLienRegistryCanEncumber() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RWAToken.RWAToken__OnlyLienRegistry.selector, alice));
        token.encumber(alice, 100e18);
    }

    function test_onlyPoolCanCreateLien() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LienRegistry.Lien__OnlyPool.selector, alice));
        liens.createLien(alice, address(token), 100e18, LOAN_REF);
    }

    /// Even the trustee cannot move a pledged balance directly — enforcement
    /// has to go through the registry, so a lien record always justifies it.
    function test_forcedTransferRejectsEveryoneButTheRegistry() public {
        _pledge(800e18);

        vm.prank(pool);
        vm.expectRevert(abi.encodeWithSelector(RWAToken.RWAToken__OnlyEnforcementAgent.selector, pool));
        token.forcedTransfer(alice, pool, 800e18, bytes32(0));

        vm.prank(trustee);
        vm.expectRevert(abi.encodeWithSelector(RWAToken.RWAToken__OnlyEnforcementAgent.selector, trustee));
        token.forcedTransfer(alice, trustee, 800e18, bytes32(0));
    }

    function test_onlyTrusteeCanInitiateForeclosure() public {
        bytes32 lienId = _pledge(800e18);

        vm.prank(pool);
        vm.expectRevert(abi.encodeWithSelector(LienRegistry.Lien__OnlySecurityTrustee.selector, pool));
        liens.foreclose(lienId);
    }

    // ─── Release ─────────────────────────────────────────────────────────────

    function test_releaseRestoresFreeBalance() public {
        bytes32 lienId = _pledge(800e18);

        vm.prank(pool);
        liens.releaseLien(lienId);

        assertEq(token.encumberedOf(alice), 0);
        assertEq(token.freeBalanceOf(alice), ALICE_HOLDING);
        assertFalse(liens.isActive(lienId));

        vm.prank(alice);
        token.transfer(bob, ALICE_HOLDING);
        assertEq(token.balanceOf(bob), ALICE_HOLDING);
    }

    function test_cannotReleaseTwice() public {
        bytes32 lienId = _pledge(800e18);

        vm.startPrank(pool);
        liens.releaseLien(lienId);
        vm.expectRevert(abi.encodeWithSelector(LienRegistry.Lien__AlreadyReleased.selector, lienId));
        liens.releaseLien(lienId);
        vm.stopPrank();
    }

    /**
     * Foreclosure must not bar the borrower from ever pledging again.
     *
     * The lien id was originally a pure function of borrower and asset, so the
     * slot stayed occupied after a charge closed and every later pledge died on
     * Lien__DuplicateLien. Anyone foreclosed once was locked out permanently,
     * which is not how credit works anywhere.
     */
    function test_canPledgeAgainAfterForeclosure() public {
        bytes32 first = _pledge(500e18);

        vm.prank(trustee);
        liens.foreclose(first);

        // The trustee took 500; 500 remain with Alice, free.
        assertEq(token.balanceOf(alice), 500e18);
        assertEq(token.encumberedOf(alice), 0);

        bytes32 second = _pledge(400e18);
        assertTrue(second != first, "a fresh charge must get a fresh id");
        assertTrue(liens.isActive(second));
        assertEq(token.encumberedOf(alice), 400e18);
    }

    function test_canPledgeAgainAfterRelease() public {
        bytes32 first = _pledge(800e18);

        vm.prank(pool);
        liens.releaseLien(first);

        bytes32 second = _pledge(800e18);
        assertTrue(second != first);
        assertTrue(liens.isActive(second));
        assertEq(liens.pledgeSequence(alice, address(token)), 1);
    }

    /// The closed charge stays readable — the register is append-only.
    function test_closedLienRemainsInTheRegister() public {
        bytes32 first = _pledge(500e18);
        vm.prank(trustee);
        liens.foreclose(first);

        _pledge(400e18);

        ILienRegistry.Lien memory old = liens.getLien(first);
        assertTrue(old.foreclosed);
        assertEq(old.amount, 500e18);
        assertGt(old.perfectedAt, 0);
    }

    // ─── Eligibility ─────────────────────────────────────────────────────────

    function test_ineligibleRecipientRejected() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RWAToken.RWAToken__RecipientNotEligible.selector, outsider));
        token.transfer(outsider, 1e18);
    }

    function test_expiredEligibilityStopsBeingEligible() public {
        vm.prank(admin);
        eligibility.grantEligibility(outsider, bytes32("IN"), uint64(block.timestamp + 10 days));
        assertTrue(eligibility.isEligible(outsider));

        vm.warp(block.timestamp + 11 days);
        assertFalse(eligibility.isEligible(outsider));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RWAToken.RWAToken__RecipientNotEligible.selector, outsider));
        token.transfer(outsider, 1e18);
    }

    // ─── Valuation ───────────────────────────────────────────────────────────

    function test_navAccretesTowardPar() public view {
        assertEq(nav.navAt(issueDate), ISSUE_PRICE);
        assertEq(nav.navAt(maturityDate), FACE_VALUE);

        uint256 midpoint = nav.navAt(issueDate + 45 days);
        assertGt(midpoint, ISSUE_PRICE);
        assertLt(midpoint, FACE_VALUE);
    }

    function test_navIsNeverStale() public {
        vm.warp(block.timestamp + 30 days);
        (, int256 answer,, uint256 updatedAt,) = nav.latestRoundData();

        // Computed on read, so it is current by construction.
        assertEq(updatedAt, block.timestamp);
        assertGt(uint256(answer), ISSUE_PRICE);
    }

    function test_navFlatAfterMaturity() public {
        vm.warp(maturityDate + 400 days);
        (, int256 answer,,,) = nav.latestRoundData();
        assertEq(uint256(answer), FACE_VALUE);
        assertTrue(nav.isMatured());
    }

    // ─── Redemption ──────────────────────────────────────────────────────────

    function test_redeemPaysAtNav() public {
        _fundIssuerReserve(200_000e18);

        uint256 expected = issuer.quoteRedemption(100e18);
        assertEq(expected, 9_875e18); // 100 tokens x $98.75

        vm.prank(alice);
        uint256 paid = issuer.redeem(100e18);

        assertEq(paid, expected);
        assertEq(stable.balanceOf(alice), expected);
        assertEq(token.balanceOf(alice), ALICE_HOLDING - 100e18);
    }

    function test_cannotRedeemPledgedBalance() public {
        _fundIssuerReserve(200_000e18);
        _pledge(800e18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RWAIssuer.RWAIssuer__NotFreeBalance.selector, 200e18, 500e18));
        issuer.redeem(500e18);
    }

    // ─── The full default path ───────────────────────────────────────────────

    /**
     * Pledge, default, foreclose, redeem, settle. Every step here has both a
     * legal name and a transaction, which is the point of the whole design.
     */
    function test_foreclosureRealisesCollateralWithoutBorrowerCooperation() public {
        _fundIssuerReserve(200_000e18);
        bytes32 lienId = _pledge(800e18);

        // Time passes; the loan goes bad. Alice does nothing to help.
        vm.warp(issueDate + 60 days);

        uint256 navAtDefault = issuer.nav();
        assertGt(navAtDefault, ISSUE_PRICE);

        // 1. The trustee enforces the charge. The balance moves for the first
        //    and only time, and only through the one authorised door.
        vm.prank(trustee);
        liens.foreclose(lienId);

        assertEq(token.balanceOf(alice), 200e18);
        assertEq(token.encumberedOf(alice), 0);
        assertEq(token.balanceOf(trustee), 800e18);
        assertFalse(liens.isActive(lienId));

        // 2. The instrument liquidates itself — no court, no auction, no buyer.
        vm.prank(trustee);
        uint256 recovered = issuer.redeem(800e18);

        assertEq(stable.balanceOf(trustee), recovered);
        assertEq(token.balanceOf(trustee), 0);

        // 3. Recovery reflects the accreted value at the time of enforcement.
        uint256 expected = (800e18 * navAtDefault) / 1e8;
        assertEq(recovered, expected);
        assertGt(recovered, (800e18 * ISSUE_PRICE) / 1e8);

        ILienRegistry.Lien memory lien = liens.getLien(lienId);
        assertTrue(lien.foreclosed);
    }

    function test_foreclosureCannotRunTwice() public {
        bytes32 lienId = _pledge(800e18);

        vm.startPrank(trustee);
        liens.foreclose(lienId);
        vm.expectRevert(abi.encodeWithSelector(LienRegistry.Lien__AlreadyForeclosed.selector, lienId));
        liens.foreclose(lienId);
        vm.stopPrank();
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    function _pledge(uint256 amount) internal returns (bytes32 lienId) {
        vm.prank(pool);
        lienId = liens.createLien(alice, address(token), amount, LOAN_REF);
    }

    function _fundIssuerReserve(uint256 amount) internal {
        stable.mint(address(this), amount);
        stable.approve(address(issuer), amount);
        issuer.fundReserve(amount);
    }
}
