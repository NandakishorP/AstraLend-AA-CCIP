// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

interface ICCIPResponseHandler {
    function ccipReceiver(Client.Any2EVMMessage memory message) external;
}
