pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {LpTokenErrors} from "../errors/Errors.sol";

contract LpToken is ERC20Burnable, Ownable {
    constructor() ERC20("Stable Coin", "SC") Ownable(msg.sender) {}

    function burn(address user, uint256 _amount) public onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert LpTokenErrors.LpToken__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert LpTokenErrors.LpToken__NotEnoughTokensToBurn(
                balance,
                _amount
            );
        }
        _burn(user, _amount);
    }
    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert LpTokenErrors.LpToken__InvalidAddress();
        }
        if (_amount <= 0) {
            revert LpTokenErrors.LpToken__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
