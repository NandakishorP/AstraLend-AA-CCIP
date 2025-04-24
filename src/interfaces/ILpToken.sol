// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ILpToken Interface
 * @notice Interface for the LP Token contract, providing functions for minting, burning, and transferring tokens.
 * @dev This interface includes essential ERC20 functions and additional functions for minting and burning LP tokens.
 */
interface ILpToken {
    /**
     * @notice Mints a specified amount of LP tokens to a given address.
     * @param _to The address that will receive the minted tokens.
     * @param _amount The amount of LP tokens to mint.
     * @return A boolean indicating whether the minting was successful.
     */
    function mint(address _to, uint256 _amount) external returns (bool);

    /**
     * @notice Burns a specified amount of LP tokens from the caller's balance.
     * @param _amount The amount of LP tokens to burn.
     */
    function burn(address user, uint256 _amount) external;

    /**
     * @notice Returns the balance of a specific account.
     * @param account The address whose balance is being queried.
     * @return The token balance of the specified account.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @notice Returns the total supply of LP tokens.
     * @return The total number of LP tokens in circulation.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Transfers a specified amount of LP tokens to a recipient address.
     * @param recipient The address to receive the tokens.
     * @param amount The amount of tokens to transfer.
     * @return A boolean indicating whether the transfer was successful.
     */
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @notice Transfers a specified amount of tokens from one address to another using an allowance mechanism.
     * @param sender The address sending the tokens.
     * @param recipient The address receiving the tokens.
     * @param amount The amount of tokens to transfer.
     * @return A boolean indicating whether the transfer was successful.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @notice Approves a spender to transfer a specified amount of tokens on behalf of the caller.
     * @param spender The address authorized to spend tokens.
     * @param amount The maximum amount the spender can transfer.
     * @return A boolean indicating whether the approval was successful.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @notice Returns the remaining number of tokens that a spender is allowed to transfer on behalf of an owner.
     * @param owner The address that owns the tokens.
     * @param spender The address authorized to spend the tokens.
     * @return The remaining allowance amount.
     */
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    /**
     * @notice Emitted when tokens are transferred from one address to another.
     * @param from The address tokens were transferred from.
     * @param to The address tokens were transferred to.
     * @param value The amount of tokens transferred.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @notice Emitted when an approval is given for a spender to transfer tokens on behalf of an owner.
     * @param owner The address that approved the allowance.
     * @param spender The address authorized to spend the tokens.
     * @param value The amount of tokens approved.
     */
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}
