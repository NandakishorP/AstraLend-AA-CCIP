// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {LienRegistry} from "../src/rwa/LienRegistry.sol";
import {EligibilityRegistry} from "../src/rwa/EligibilityRegistry.sol";
import {TBillNavOracle} from "../src/rwa/TBillNavOracle.sol";
import {LendingPoolContract} from "../src/LendingPoolContract.sol";
import {IGlobalStateManager} from "../src/interfaces/IGlobalStateManager.sol";
import {MockERC3643} from "../test/mocks/MockERC3643.sol";
import {MockRedemptionDesk} from "../test/mocks/MockRedemptionDesk.sol";

/**
 * Wires the protocol up to lend against a third-party tokenised security.
 *
 * We are not the issuer. Everything under "the issuer's world" below would
 * already exist in a real deployment — Ondo's OUSG, a Tokeny issuance — and the
 * protocol would simply be pointed at its address. It is deployed here because
 * a local chain has no securities on it, exactly as MockCCIPRouter is deployed
 * because a local chain has no DON.
 *
 * The single line that matters is `token.addAgent(address(liens))`. That is the
 * on-chain half of the tri-party agreement: the issuer authorising the
 * protocol's registry to freeze a holder's balance in place and, on default, to
 * force it out. Without it every pledge reverts. It is a business relationship
 * before it is a transaction, and it is the real dependency of this design.
 *
 * Hub only. The security exists on one chain; only messages about the charge
 * ever cross.
 *
 * Required environment:
 *   LENDING_POOL      hub pool proxy, already deployed and initialised
 *   STABLE_COIN       currency the redemption desk pays in
 *   GSM               global state manager, for seeding the borrower index
 *   DEMO_HOLDER       receives the security and is verified to hold it
 *   SECURITY_TRUSTEE  may enforce a charge; a different legal party to the holder
 */
contract DeployRwa is Script {
    // A government bill carries a far smaller haircut than a volatile crypto
    // asset, which is the entire reason per-asset risk parameters exist.
    uint256 private constant RWA_LTV = 95e16;
    uint256 private constant RWA_LIQUIDATION_THRESHOLD = 97e16;

    // 364 days, not 91. LoanController fixes every loan at 180 days and refuses
    // one that would outlive its collateral, so a 91-day bill cannot back a
    // standard loan at all. RBI issues 91, 182 and 364-day tenors.
    uint256 private constant ISSUE_PRICE = 95_20000000;
    uint256 private constant FACE_VALUE = 100_00000000;
    uint64 private constant TENOR = 364 days;

    uint64 private constant RWA_TOKEN_ID = 10;
    uint256 private constant HOLDER_ALLOCATION = 1_000e18;

    function run() external {
        address pool = vm.envAddress("LENDING_POOL");
        address stableCoin = vm.envAddress("STABLE_COIN");
        address demoHolder = vm.envAddress("DEMO_HOLDER");
        address securityTrustee = vm.envAddress("SECURITY_TRUSTEE");

        vm.startBroadcast();
        address deployer = msg.sender;

        // ─── The issuer's world — not ours ───────────────────────────────────
        EligibilityRegistry identity = new EligibilityRegistry(deployer);
        MockERC3643 security = new MockERC3643("Treasury Bill 364D", "TBILL364", 18, deployer);
        security.setIdentityRegistry(address(identity));

        TBillNavOracle navOracle = new TBillNavOracle(
            "364-day Treasury Bill",
            ISSUE_PRICE,
            FACE_VALUE,
            uint64(block.timestamp),
            uint64(block.timestamp) + TENOR
        );

        // ─── The protocol's world ────────────────────────────────────────────
        LienRegistry liens = new LienRegistry(deployer);

        // The registry's authorised caller is the CollateralController, not the
        // pool proxy: the pool delegates collateral handling, so the controller
        // is what actually calls createLien.
        address collateralController =
            LendingPoolContract(payable(pool)).getCollateralControllerAddress();
        liens.setPool(collateralController);
        liens.setSecurityTrustee(securityTrustee);

        // ─── The tri-party agreement, on-chain ───────────────────────────────
        security.addAgent(address(liens));
        security.addAgent(deployer); // issuer keeps its own rights, for minting

        // Holders must be verified. The trustee too — a security cannot be
        // forced into an ineligible wallet even by enforcement.
        identity.grantEligibility(demoHolder, bytes32("IN"), uint64(block.timestamp + 400 days));
        identity.grantEligibility(securityTrustee, bytes32("IN"), uint64(block.timestamp + 400 days));

        // ─── Register with the pool ──────────────────────────────────────────
        LendingPoolContract(payable(pool)).addRwaAsset(
            RWA_TOKEN_ID, address(security), address(navOracle), RWA_LTV, RWA_LIQUIDATION_THRESHOLD
        );
        LendingPoolContract(payable(pool)).setLienRegistry(address(liens));

        // Interest accrual is index-based and repayment divides by the index the
        // loan was stamped with. Without this the asset can be borrowed against
        // and never repaid.
        IGlobalStateManager(vm.envAddress("GSM")).setInitialBorrowerIndex(RWA_TOKEN_ID);

        // ─── Realisation venue — off-chain in reality ────────────────────────
        MockRedemptionDesk desk =
            new MockRedemptionDesk(address(security), stableCoin, address(navOracle), 18, 18);
        identity.grantEligibility(address(desk), bytes32("IN"), uint64(block.timestamp + 400 days));

        security.mint(demoHolder, HOLDER_ALLOCATION);

        // Fail here rather than at a borrower's first pledge.
        liens.assertIsAgent(address(security));

        vm.stopBroadcast();

        console.log("DEPLOY rwaSecurity=%s", address(security));
        console.log("DEPLOY rwaLienRegistry=%s", address(liens));
        console.log("DEPLOY rwaIdentityRegistry=%s", address(identity));
        console.log("DEPLOY rwaNavOracle=%s", address(navOracle));
        console.log("DEPLOY rwaRedemptionDesk=%s", address(desk));
        console.log("RWA tokenId=%s ltv=%s", RWA_TOKEN_ID, RWA_LTV);
        console.log("RWA maturity=%s", uint256(block.timestamp) + TENOR);
        console.log("RWA holder=%s allocation=%s", demoHolder, HOLDER_ALLOCATION);
        console.log("RWA trustee=%s", securityTrustee);
        console.log("RWA agent=%s (registry appointed on the security)", address(liens));
    }
}
