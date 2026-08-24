// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {TBillNavOracle} from "../src/rwa/TBillNavOracle.sol";
import {LendingPoolContract} from "../src/LendingPoolContract.sol";
import {IStateAggregator} from "../src/interfaces/IStateAggregator.sol";

/**
 * Registers the hub's instrument on a satellite so it can be borrowed against.
 *
 * No token, no issuer, no lien registry here — none of them belong on this
 * chain. The instrument stays on the hub and the satellite only ever learns
 * that a charge exists, through the mirrored collateral message.
 *
 * What the satellite does need is a way to *value* what it has been told about.
 * For a Treasury bill that costs nothing: the value is a deterministic function
 * of issue price, face value and dates, so an identical oracle deployed here
 * computes exactly the same number as the hub's, with no price feed, no
 * cross-chain quote and nothing to keep in sync.
 *
 * They are not bit-identical, and the reason is worth knowing: accretion is a
 * function of block.timestamp, and two chains do not share a clock. Measured on
 * the local pair the answers differ by roughly 3e3 out of 9.5e9 — a few seconds
 * of a 364-day discount, fractions of a paisa. The curve is identical; only the
 * point sampled on it drifts. Well inside a 5% haircut, but it is a divergence
 * rather than an equality and should be described as one.
 *
 * That is a property of the instrument rather than of this design — it would
 * not hold for an asset whose value has to be observed. An attested NAV would
 * have to be messaged across like any other state.
 *
 * `tokenAddress` is registered as the hub's address. Nothing lives there on this
 * chain, and that is correct: it identifies which instrument secures the loan,
 * and the canonical identity of the instrument is its hub address.
 *
 * Required environment:
 *   LENDING_POOL   the satellite pool proxy
 *   RWA_TOKEN      the hub's token address, recorded as the instrument's identity
 *   ISSUE_PRICE / FACE_VALUE / ISSUE_DATE / MATURITY_DATE
 *                  copied verbatim from the hub oracle so the curves match
 */
contract DeployRwaSatellite is Script {
    uint256 private constant RWA_LTV = 95e16;
    uint256 private constant RWA_LIQUIDATION_THRESHOLD = 97e16;
    uint64 private constant RWA_TOKEN_ID = 10;

    function run() external {
        address pool = vm.envAddress("LENDING_POOL");
        address rwaToken = vm.envAddress("RWA_TOKEN");

        vm.startBroadcast();

        TBillNavOracle navOracle = new TBillNavOracle(
            "364-day Treasury Bill",
            vm.envUint("ISSUE_PRICE"),
            vm.envUint("FACE_VALUE"),
            uint64(vm.envUint("ISSUE_DATE")),
            uint64(vm.envUint("MATURITY_DATE"))
        );

        LendingPoolContract(payable(pool)).addRwaAsset(
            RWA_TOKEN_ID,
            rwaToken,
            address(navOracle),
            RWA_LTV,
            RWA_LIQUIDATION_THRESHOLD
        );

        // Same reasoning as the hub: the satellite stamps loans with this index
        // and repayment divides by it.
        IStateAggregator(vm.envAddress("STATE_AGGREGATOR")).setInitialBorrowerIndex(RWA_TOKEN_ID);

        vm.stopBroadcast();

        console.log("DEPLOY rwaNavOracleSatellite=%s", address(navOracle));
        console.log("RWA satellite tokenId=%s registered", RWA_TOKEN_ID);
    }
}
