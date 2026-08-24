// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {RWAToken} from "../src/rwa/RWAToken.sol";
import {RWAIssuer} from "../src/rwa/RWAIssuer.sol";
import {LienRegistry} from "../src/rwa/LienRegistry.sol";
import {EligibilityRegistry} from "../src/rwa/EligibilityRegistry.sol";
import {TBillNavOracle} from "../src/rwa/TBillNavOracle.sol";
import {LendingPoolContract} from "../src/LendingPoolContract.sol";

/**
 * Deploys the real-world asset module onto an existing hub deployment.
 *
 * Hub only, and that is structural rather than a simplification. The instrument
 * exists on one chain and never moves; the satellite learns about the charge
 * through a mirrored message and needs none of these contracts.
 *
 * Console output follows the `DEPLOY key=0x…` convention that
 * tooling/deploy-local.mjs parses.
 *
 * Required environment:
 *   LENDING_POOL      the hub pool proxy, already deployed and initialised
 *   STABLE_COIN       used for the issuer's redemption reserve
 *   DEMO_HOLDER       receives the bill and is marked eligible
 *   SECURITY_TRUSTEE  may enforce a charge; kept distinct from the holder
 *                     because they are different legal parties, and distinct
 *                     from the deployer because tooling/relayer.mjs signs with
 *                     the deployer key and would race it for nonces
 */
contract DeployRwa is Script {
    // Risk. A 91-day government bill carries a far smaller haircut than a
    // volatile crypto asset — which is the entire reason per-asset parameters
    // had to exist before this could be registered.
    uint256 private constant RWA_LTV = 95e16;
    uint256 private constant RWA_LIQUIDATION_THRESHOLD = 97e16;

    // The instrument: bought at a discount, redeems at par. 8 decimals, matching
    // the Chainlink convention the pool already scales for.
    //
    // 364 days, not 91, and the reason is a real constraint rather than taste.
    // LoanController fixes every loan at 180 days, and a loan may not outlive
    // the instrument securing it, so a 91-day bill cannot back a standard loan
    // at all — the borrow reverts with LoanController__LoanOutlivesCollateral.
    // RBI issues 91, 182 and 364-day bills; only the longest works until loan
    // tenor becomes configurable.
    uint256 private constant ISSUE_PRICE = 95_20000000;
    uint256 private constant FACE_VALUE = 100_00000000;
    uint64 private constant TENOR = 364 days;

    /// Sits above the crypto assets registered by index in initialize.
    uint64 private constant RWA_TOKEN_ID = 10;

    uint256 private constant HOLDER_ALLOCATION = 1_000e18;

    function run() external {
        address pool = vm.envAddress("LENDING_POOL");
        address stableCoin = vm.envAddress("STABLE_COIN"); // issuer redemption currency
        address demoHolder = vm.envAddress("DEMO_HOLDER");
        address securityTrustee = vm.envAddress("SECURITY_TRUSTEE");

        vm.startBroadcast();
        address deployer = msg.sender;

        // ─── The instrument and its supporting cast ──────────────────────────
        EligibilityRegistry eligibility = new EligibilityRegistry(deployer);
        RWAToken token = new RWAToken("Treasury Bill 364D", "TBILL364", 18, deployer);
        LienRegistry liens = new LienRegistry(deployer);
        RWAIssuer issuer = new RWAIssuer(address(token), stableCoin, 18, deployer);

        TBillNavOracle navOracle = new TBillNavOracle(
            "364-day Treasury Bill",
            ISSUE_PRICE,
            FACE_VALUE,
            uint64(block.timestamp),
            uint64(block.timestamp) + TENOR
        );

        // ─── Roles ───────────────────────────────────────────────────────────
        // Each address here is one legal party. The enforcement agent is the
        // registry rather than the trustee's own address, so a pledged balance
        // can only move against a recorded lien, at a legal person's direction.
        token.setLienRegistry(address(liens));
        token.setEnforcementAgent(address(liens));
        token.setIssuer(address(issuer));
        token.setEligibilityRegistry(address(eligibility));
        token.setTrustDeed(keccak256("ASTRALEND_TRUST_DEED_V1"), "ipfs://astralend-trust-deed-v1");

        // The registry's authorised caller is the CollateralController, not the
        // pool proxy. The pool delegates collateral handling to it, so the
        // controller is what actually calls createLien — pointing this at the
        // proxy reverts with Lien__OnlyPool(controller).
        address collateralController =
            LendingPoolContract(payable(pool)).getCollateralControllerAddress();
        liens.setPool(collateralController);
        liens.setSecurityTrustee(securityTrustee);
        issuer.setValuation(address(navOracle));

        // ─── Eligibility ─────────────────────────────────────────────────────
        // The trustee must be eligible too: foreclosure transfers the balance to
        // it, and the holder restriction applies to that transfer like any other.
        eligibility.grantEligibility(demoHolder, bytes32("IN"), uint64(block.timestamp + 400 days));
        eligibility.grantEligibility(securityTrustee, bytes32("IN"), uint64(block.timestamp + 400 days));

        // ─── Register with the pool ──────────────────────────────────────────
        // The NAV oracle goes straight into the price feed slot. It satisfies
        // AggregatorV3Interface, so collateral valuation, health factors,
        // liquidation and the keeper need no change at all.
        LendingPoolContract(payable(pool)).addRwaAsset(
            RWA_TOKEN_ID,
            address(token),
            address(navOracle),
            RWA_LTV,
            RWA_LIQUIDATION_THRESHOLD
        );
        LendingPoolContract(payable(pool)).setLienRegistry(address(liens));

        // ─── Seed the demo ───────────────────────────────────────────────────
        issuer.mint(demoHolder, HOLDER_ALLOCATION);

        // The redemption reserve is deliberately NOT funded here. In a real
        // deployment stablecoin arrives because the custodian sold or redeemed
        // the underlying and remitted the proceeds — an obligation of the trust
        // deed that no deploy script can discharge. Locally it is seeded by
        // tooling/rwa-scenario.mjs, which is honest about needing to impersonate
        // the stablecoin's owner to do it.

        vm.stopBroadcast();

        console.log("DEPLOY rwaToken=%s", address(token));
        console.log("DEPLOY rwaIssuer=%s", address(issuer));
        console.log("DEPLOY rwaLienRegistry=%s", address(liens));
        console.log("DEPLOY rwaEligibility=%s", address(eligibility));
        console.log("DEPLOY rwaNavOracle=%s", address(navOracle));
        console.log("RWA tokenId=%s ltv=%s", RWA_TOKEN_ID, RWA_LTV);
        console.log("RWA maturity=%s", uint256(block.timestamp) + TENOR);
        console.log("RWA holder=%s allocation=%s", demoHolder, HOLDER_ALLOCATION);
        console.log("RWA trustee=%s", securityTrustee);
        console.log("RWA collateralController=%s", collateralController);
        console.log("RWA reserve=UNFUNDED (seed with tooling/rwa-scenario.mjs)");
    }
}
