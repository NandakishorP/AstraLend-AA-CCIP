// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title LpToken
 * @notice LP Token contract that supports minting and burning of tokens.
 * @dev This contract extends ERC20 and ERC20Burnable, with the owner having exclusive minting and burning privileges.
 *      Custom errors are used for more efficient error handling.
 */
contract LpToken is ERC20Burnable, Ownable {
    ////////////////////
    // Error
    ////////////////////
    error LpToken__AmountMustBeMoreThanZero();
    error LpToken__NotEnoughTokensToBurn(
        uint256 userBalance,
        uint256 amountProvided
    );
    error LpToken__InvalidAddress();

    /**
     * @notice Constructor to initialize the LpToken contract.
     * @dev Sets the name to "Stable Coin" and symbol to "SC". Assigns ownership to the deployer.
     */
    constructor() ERC20("Stable Coin", "SC") Ownable(msg.sender) {}

    // the mint and the burn functions are limited to the contract itself because its necessery for the contract to track how much
    // token is in supply who has how much and all on behalf of the protocol not on behalf of the user

    /**
     * @notice Burns a specified amount of tokens from the owner's account.
     * @dev This function overrides the burn function from ERC20Burnable. Only the contract owner can call it.
     *      It checks that the amount is greater than zero and ensures the owner's balance is sufficient.
     * @param _amount The amount of tokens to burn.
     *
     * @custom:reverts
     * - `LpToken__AmountMustBeMoreThanZero` if the provided amount is zero or negative.
     * - `LpToken__NotEnoughTokensToBurn` if the owner's balance is insufficient.
     */
    function burn(address user, uint256 _amount) public onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert LpToken__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert LpToken__NotEnoughTokensToBurn(balance, _amount);
        }
        _burn(user, _amount);
    }

    /**
     * @notice Mints a specified amount of tokens to a given address.
     * @dev Only the contract owner can call this function. It ensures the recipient address is valid
     *      and the mint amount is greater than zero.
     * @param _to The address that will receive the minted tokens.
     * @param _amount The amount of tokens to mint.
     * @return A boolean indicating whether the minting was successful.
     *
     * @custom:reverts
     * - `LpToken__InvalidAddress` if the recipient address is invalid (zero address).
     * - `LpToken__AmountMustBeMoreThanZero` if the mint amount is zero or negative.
     */
    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert LpToken__InvalidAddress();
        }
        if (_amount <= 0) {
            revert LpToken__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
