pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {StableCoinErrors} from "../errors/Errors.sol";

contract StableCoin is ERC20, Ownable {
    constructor() ERC20("Stable Coin", "SC") Ownable(msg.sender) {}
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
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}
