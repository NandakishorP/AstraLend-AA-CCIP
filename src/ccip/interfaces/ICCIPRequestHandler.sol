// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {LendingPoolContract} from "../../LendingPoolContract.sol";

interface ICCIPRequestHandler {
    function getCollateralInformation(
        Client.Any2EVMMessage memory message,
        LendingPoolContract.CrossChainRequestPayLoad memory requestPayLoad
    ) external;

    function updateCollateralDetailsOfUser(
        LendingPoolContract.CrossChainPayLoad memory actionPayLoad
    ) external;
}
