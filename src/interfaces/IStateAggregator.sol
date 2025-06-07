// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {CollateralStateMirror} from "../StateMirror/CollateralStateMirror.sol";

interface IStateAggregator {
    function updateCollateralDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        CollateralStateMirror.CollateralDetailsOfUser
            memory collateralDetailsOfUser_
    ) external;

    function readCollateralDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256);
}
