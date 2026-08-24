pragma solidity ^0.8.20;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";

contract CollateralStateMirror is Ownable {
    constructor() Ownable(msg.sender) {}


    struct CollateralDetailsOfUser {
        uint256 amount;
        uint256 lastUpdatedTime;
    }


    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => CollateralDetailsOfUser)))
        private s_userCollateralDetails;


    function updateCollateralDetaiilsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        CollateralDetailsOfUser memory collateralDetailsOfUser_
    ) external onlyOwner {
        s_userCollateralDetails[chainId][user][
            tokenId
        ] = collateralDetailsOfUser_;
    }


    function readCollateralDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view onlyOwner returns (CollateralDetailsOfUser memory) {
        return s_userCollateralDetails[chainId][user][tokenId];
    }
}
