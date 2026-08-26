// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {LienRegistry} from "../../src/rwa/LienRegistry.sol";
import {EligibilityRegistry} from "../../src/rwa/EligibilityRegistry.sol";
import {TBillNavOracle} from "../../src/rwa/TBillNavOracle.sol";
import {ILienRegistry} from "../../src/rwa/interfaces/ILienRegistry.sol";
import {MockERC3643} from "../mocks/MockERC3643.sol";
import {MockRedemptionDesk} from "../mocks/MockRedemptionDesk.sol";
import {StableCoin} from "../../src/tokens/StableCoin.sol";

/**
 * Encumbered collateral over a third-party ERC-3643 security.
 *
 * The collateral is not ours. It is somebody else's tokenised Treasury bill,
 * and the immobilisation is the token's own partial-freeze — the standard
 * already enforces `transfer <= balance - frozen`. What the protocol supplies
 * is the register of charges and the authority, granted by the issuer, to
 * operate that freeze on a borrower's behalf.
 *
 * So these tests are really asking one question: given agent rights on a
 * conforming token, can a lender pledge a holding in place, refuse to let
 * anyone move it, and realise it on default — without ever taking custody?
 */
contract RWACollateralTest is Test {
    MockERC3643 internal token;
    LienRegistry internal liens;
    EligibilityRegistry internal identity;
    TBillNavOracle internal nav;
    MockRedemptionDesk internal desk;
    StableCoin internal stable;

    address internal issuer = makeAddr("issuerSPV");
    address internal trustee = makeAddr("securityTrustee");
    address internal pool = makeAddr("collateralController");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal outsider = makeAddr("unverifiedExchange");

    uint256 internal constant ISSUE_PRICE = 95_20000000;
    uint256 internal constant FACE_VALUE = 100_00000000;
    uint64 internal issueDate;
    uint64 internal maturityDate;

    uint256 internal constant ALICE_HOLDING = 1_000e18;
    bytes32 internal constant LOAN_REF = keccak256("loan-42");

    function setUp() public {
        issueDate = uint64(block.timestamp);
        maturityDate = uint64(block.timestamp + 364 days);

        stable = new StableCoin();
        nav = new TBillNavOracle("364-day T-Bill", ISSUE_PRICE, FACE_VALUE, issueDate, maturityDate);

        // The issuer's world: their token, their identity registry.
        vm.startPrank(issuer);
        identity = new EligibilityRegistry(issuer);
        token = new MockERC3643("Treasury Bill 364D", "TBILL364", 18, issuer);
        token.setIdentityRegistry(address(identity));
        identity.grantEligibility(alice, bytes32("IN"), uint64(block.timestamp + 400 days));
        identity.grantEligibility(bob, bytes32("IN"), uint64(block.timestamp + 400 days));
        identity.grantEligibility(trustee, bytes32("IN"), uint64(block.timestamp + 400 days));
        vm.stopPrank();

        // Our world: the register of charges.
        liens = new LienRegistry(address(this));
        liens.setPool(pool);
        liens.setSecurityTrustee(trustee);

        // The tri-party agreement, on-chain: the issuer appoints our registry.
        vm.startPrank(issuer);
        token.addAgent(address(liens));
        token.addAgent(issuer);
        token.mint(alice, ALICE_HOLDING);
        vm.stopPrank();

        desk = new MockRedemptionDesk(address(token), address(stable), address(nav), 18, 18);
        vm.prank(issuer);
        identity.grantEligibility(address(desk), bytes32("IN"), uint64(block.timestamp + 400 days));
    }

    // ─── The appointment is the whole dependency ─────────────────────────────

    function test_registryMustBeAnAgentToPledge() public {
        vm.prank(issuer);
        token.removeAgent(address(liens));

        vm.prank(pool);
        vm.expectRevert(abi.encodeWithSelector(MockERC3643.MockERC3643__NotAgent.selector, address(liens)));
        liens.createLien(alice, address(token), 800e18, LOAN_REF);
    }

    function test_assertIsAgentSurfacesAMisconfiguredDeployment() public {
        liens.assertIsAgent(address(token)); // configured: passes

        vm.prank(issuer);
        token.removeAgent(address(liens));

        vm.expectRevert(
            abi.encodeWithSelector(LienRegistry.Lien__NotAnAgentOnToken.selector, address(token), address(liens))
        );
        liens.assertIsAgent(address(token));
    }

    // ─── The core rule, enforced by the issuer's contract ────────────────────

    function test_freeBalanceTransfersNormally() public {
        vm.prank(alice);
        token.transfer(bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
    }

    function test_frozenBalanceCannotBeTransferred() public {
        _pledge(800e18);

        // Balance untouched. The bill never left Alice's wallet.
        assertEq(token.balanceOf(alice), ALICE_HOLDING);
        assertEq(token.getFrozenTokens(alice), 800e18);
        assertEq(token.freePartialBalanceOf(alice), 200e18);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(MockERC3643.MockERC3643__InsufficientFreeBalance.selector, 200e18, 900e18)
        );
        token.transfer(bob, 900e18);
    }

    function test_freeRemainderStillMovesWhilePledged() public {
        _pledge(800e18);
        vm.prank(alice);
        token.transfer(bob, 200e18);
        assertEq(token.balanceOf(bob), 200e18);
    }

    /// The ordinary DeFi deposit path, which must fail against a pledged
    /// holding — otherwise the same collateral backs two loans at two venues.
    function test_anotherProtocolCannotPullPledgedTokens() public {
        _pledge(800e18);

        address rivalPool = bob;
        vm.prank(alice);
        token.approve(rivalPool, ALICE_HOLDING);

        vm.prank(rivalPool);
        vm.expectRevert(
            abi.encodeWithSelector(MockERC3643.MockERC3643__InsufficientFreeBalance.selector, 200e18, 800e18)
        );
        token.transferFrom(alice, rivalPool, 800e18);
    }

    // ─── Double-pledge prevention lives in the token ─────────────────────────

    function test_cannotFreezeBeyondBalance() public {
        _pledge(800e18);

        vm.prank(pool);
        vm.expectRevert(
            abi.encodeWithSelector(
                MockERC3643.MockERC3643__FreezeExceedsBalance.selector, ALICE_HOLDING, 800e18, 300e18
            )
        );
        liens.createLien(alice, address(token), 300e18, keccak256("loan-43"));
    }

    /// A second agent — another lender entirely — still cannot over-freeze,
    /// because every agent increments the same counter on the same token.
    function test_aSecondLenderCannotOverFreezeTheSameHolding() public {
        _pledge(800e18);

        address rivalLender = makeAddr("rivalLender");
        vm.prank(issuer);
        token.addAgent(rivalLender);

        vm.prank(rivalLender);
        vm.expectRevert(
            abi.encodeWithSelector(
                MockERC3643.MockERC3643__FreezeExceedsBalance.selector, ALICE_HOLDING, 800e18, 300e18
            )
        );
        token.freezePartialTokens(alice, 300e18);

        // They may take the free remainder, and no more.
        vm.prank(rivalLender);
        token.freezePartialTokens(alice, 200e18);
        assertEq(token.getFrozenTokens(alice), ALICE_HOLDING);
    }

    function test_secondLienAllowedAgainstFreeRemainder() public {
        _pledge(800e18);
        vm.prank(pool);
        liens.createLien(alice, address(token), 200e18, keccak256("loan-43"));
        assertEq(token.getFrozenTokens(alice), ALICE_HOLDING);
    }

    // ─── Running-account charge ──────────────────────────────────────────────

    function test_increaseLienDeepensTheSameCharge() public {
        bytes32 lienId = _pledge(500e18);
        vm.prank(pool);
        liens.increaseLien(lienId, 300e18);

        assertEq(token.getFrozenTokens(alice), 800e18);
        assertEq(liens.getLien(lienId).amount, 800e18);
    }

    function test_decreaseLienFreesCollateral() public {
        bytes32 lienId = _pledge(800e18);
        vm.prank(pool);
        liens.decreaseLien(lienId, 300e18);

        assertEq(token.getFrozenTokens(alice), 500e18);
        vm.prank(alice);
        token.transfer(bob, 500e18);
        assertEq(token.balanceOf(bob), 500e18);
    }

    // ─── Access control ──────────────────────────────────────────────────────

    function test_onlyPoolCanCreateLien() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LienRegistry.Lien__OnlyPool.selector, alice));
        liens.createLien(alice, address(token), 100e18, LOAN_REF);
    }

    function test_onlyTrusteeCanInitiateForeclosure() public {
        bytes32 lienId = _pledge(800e18);
        vm.prank(pool);
        vm.expectRevert(abi.encodeWithSelector(LienRegistry.Lien__OnlySecurityTrustee.selector, pool));
        liens.foreclose(lienId);
    }

    function test_borrowerCannotUnfreezeTheirOwnCollateral() public {
        _pledge(800e18);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MockERC3643.MockERC3643__NotAgent.selector, alice));
        token.unfreezePartialTokens(alice, 800e18);
    }

    // ─── Release ─────────────────────────────────────────────────────────────

    function test_releaseRestoresFreeBalance() public {
        bytes32 lienId = _pledge(800e18);
        vm.prank(pool);
        liens.releaseLien(lienId);

        assertEq(token.getFrozenTokens(alice), 0);
        assertFalse(liens.isActive(lienId));

        vm.prank(alice);
        token.transfer(bob, ALICE_HOLDING);
        assertEq(token.balanceOf(bob), ALICE_HOLDING);
    }

    // ─── Holder restriction is the issuer's, not ours ────────────────────────

    function test_unverifiedRecipientRejected() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(MockERC3643.MockERC3643__RecipientNotVerified.selector, outsider)
        );
        token.transfer(outsider, 1e18);
    }

    function test_foreclosureCannotPushIntoAnUnverifiedWallet() public {
        bytes32 lienId = _pledge(800e18);

        vm.prank(issuer);
        identity.revokeEligibility(trustee);

        vm.prank(trustee);
        vm.expectRevert(
            abi.encodeWithSelector(MockERC3643.MockERC3643__RecipientNotVerified.selector, trustee)
        );
        liens.foreclose(lienId);
    }

    // ─── Valuation ───────────────────────────────────────────────────────────

    function test_navAccretesTowardPar() public view {
        assertEq(nav.navAt(issueDate), ISSUE_PRICE);
        assertEq(nav.navAt(maturityDate), FACE_VALUE);
        assertGt(nav.navAt(issueDate + 180 days), ISSUE_PRICE);
    }

    function test_navIsNeverStale() public {
        vm.warp(block.timestamp + 30 days);
        (,,, uint256 updatedAt,) = nav.latestRoundData();
        assertEq(updatedAt, block.timestamp);
    }

    // ─── The full default path ───────────────────────────────────────────────

    /**
     * Foreclosure, then realisation. Note there is no unfreeze step: ERC-3643's
     * forcedTransfer unfreezes the shortfall itself, which is why the registry
     * must not attempt it separately.
     */
    function test_foreclosureRealisesCollateralWithoutBorrowerCooperation() public {
        _fundDesk(200_000e18);
        bytes32 lienId = _pledge(800e18);

        vm.warp(issueDate + 120 days);
        uint256 priceAtDefault = uint256(_navNow());
        assertGt(priceAtDefault, ISSUE_PRICE);

        vm.prank(trustee);
        liens.foreclose(lienId);

        assertEq(token.balanceOf(alice), 200e18);
        assertEq(token.getFrozenTokens(alice), 0, "no freeze may survive a discharged charge");
        assertEq(token.balanceOf(trustee), 800e18);

        uint256 expected = desk.quote(800e18);
        vm.startPrank(trustee);
        token.approve(address(desk), 800e18);
        uint256 recovered = desk.sell(800e18);
        vm.stopPrank();

        assertEq(recovered, expected);
        assertEq(stable.balanceOf(trustee), recovered);
        assertGt(recovered, (800e18 * ISSUE_PRICE) / 1e8);

        ILienRegistry.Lien memory lien = liens.getLien(lienId);
        assertTrue(lien.foreclosed);
    }

    /**
     * Foreclosure must take the pledged tokens, not the borrower's free ones.
     *
     * ERC-3643's forcedTransfer unfreezes only the shortfall, so it spends free
     * balance first. Calling it directly on an 800 charge against a holder with
     * 200 free consumes those 200 and leaves 200 frozen behind — a freeze with
     * no lien backing it, clearable only by an agent. The registry discharges
     * the exact charge first to avoid that.
     */
    function test_foreclosureLeavesNoOrphanedFreeze() public {
        bytes32 lienId = _pledge(800e18);
        assertEq(token.freePartialBalanceOf(alice), 200e18);

        vm.prank(trustee);
        liens.foreclose(lienId);

        assertEq(token.balanceOf(alice), 200e18);
        assertEq(token.getFrozenTokens(alice), 0);
        // The remainder is genuinely hers again, not stranded behind a freeze.
        assertEq(token.freePartialBalanceOf(alice), 200e18);

        vm.prank(alice);
        token.transfer(bob, 200e18);
        assertEq(token.balanceOf(bob), 200e18);
    }

    function test_canPledgeAgainAfterForeclosure() public {
        bytes32 first = _pledge(500e18);
        vm.prank(trustee);
        liens.foreclose(first);

        bytes32 second = _pledge(400e18);
        assertTrue(second != first, "a fresh charge must get a fresh id");
        assertTrue(liens.isActive(second));
        assertEq(token.getFrozenTokens(alice), 400e18);
    }

    function test_closedLienRemainsInTheRegister() public {
        bytes32 first = _pledge(500e18);
        vm.prank(trustee);
        liens.foreclose(first);
        _pledge(400e18);

        ILienRegistry.Lien memory old = liens.getLien(first);
        assertTrue(old.foreclosed);
        assertEq(old.amount, 500e18);
    }

    function test_borrowerCannotSellPledgedCollateralToTheDesk() public {
        _fundDesk(200_000e18);
        _pledge(800e18);

        vm.startPrank(alice);
        token.approve(address(desk), 800e18);
        vm.expectRevert(
            abi.encodeWithSelector(MockERC3643.MockERC3643__InsufficientFreeBalance.selector, 200e18, 800e18)
        );
        desk.sell(800e18);
        vm.stopPrank();
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    function _pledge(uint256 amount) internal returns (bytes32 lienId) {
        vm.prank(pool);
        lienId = liens.createLien(alice, address(token), amount, LOAN_REF);
    }

    function _fundDesk(uint256 amount) internal {
        stable.mint(address(this), amount);
        stable.approve(address(desk), amount);
        desk.fund(amount);
    }

    function _navNow() internal view returns (int256 answer) {
        (, answer,,,) = nav.latestRoundData();
    }
}
