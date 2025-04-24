// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {LpToken} from "../../src/LpTokenContract.sol";
import {ILpToken} from "../../src/interfaces/ILpToken.sol";

contract LpTokenTest is Test {
    LpToken lpToken;
    address user = makeAddr("user");
    address owner;

    function setUp() public {
        lpToken = new LpToken();
        owner = lpToken.owner();
    }

    function testMintingExpectingRevertBecauseAmountIsZero() public {
        vm.prank(owner);
        vm.expectRevert();
        ILpToken(address(lpToken)).mint(user, 0);
    }
}
