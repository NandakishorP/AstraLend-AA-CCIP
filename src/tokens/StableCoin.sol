// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {StableCoinErrors} from "../errors/Errors.sol";

/**
 * @title StableCoin
 * @notice A stablecoin contract that supports minting and burning of tokens.
 * @dev This contract extends ERC20 and ERC20Burnable, allowing the owner to mint and burn tokens.
 *      Custom errors are used for more efficient error handling.
 */
contract StableCoin is ERC20, Ownable {
    ////////////////////
    // Error
    ////////////////////

    /**
     * @notice Constructor to initialize the StableCoin contract.
     * @dev Sets the name to "Stable Coin" and symbol to "SC". Assigns ownership to the deployer.
     */
    constructor() ERC20("Stable Coin", "SC") Ownable(msg.sender) {}

    /**
     * @notice Mints a specified amount of tokens to a given address.
     * @dev Only the contract owner can call this function. It ensures the recipient address is valid
     *      and the mint amount is greater than zero.
     * @param _to The address that will receive the minted tokens.
     * @param _amount The amount of tokens to mint.
     * @return A boolean indicating whether the minting was successful.
     *
     * @custom:reverts
     * - `StableCoin__InvalidAddress` if the recipient address is invalid (zero address).
     * - `StableCoin__AmountMustBeMoreThanZero` if the mint amount is zero or negative.
     */
    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert StableCoinErrors.StableCoin__InvalidAddress();
        }
        if (_amount <= 0) {
            revert StableCoinErrors.StableCoin__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
