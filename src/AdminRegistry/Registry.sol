// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";

contract Registry is Ownable {
    mapping(uint256 => mapping(bytes32 => address)) private registry;

    mapping(uint64 destinationChainSelector => mapping(bytes32 => address))
        private crossChainRegistry;
    mapping(uint256 chainId => uint64) private destinationChainSelector;

    constructor() Ownable(msg.sender) {}

    event AddressSet(
        uint256 indexed chainId,
        bytes32 indexed name,
        address indexed addr
    );

    function setDestinationChainSelector(
        uint256 chainId,
        uint64 destinationChainSelector_
    ) external onlyOwner {
        destinationChainSelector[chainId] = destinationChainSelector_;
    }

    function setCrossChainRegistryAddress(
        uint64 destinationChainSelector_,
        string calldata name,
        address addr
    ) external onlyOwner {
        require(addr != address(0), "Invalid address");
        crossChainRegistry[destinationChainSelector_][
            keccak256(abi.encodePacked(name))
        ] = addr;
        emit AddressSet(
            uint256(destinationChainSelector_),
            keccak256(abi.encodePacked(name)),
            addr
        );
    }

    function setAddress(
        uint256 chainId,
        string calldata name,
        address addr
    ) external onlyOwner {
        require(addr != address(0), "Invalid address");
        registry[chainId][keccak256(abi.encodePacked(name))] = addr;
        emit AddressSet(chainId, keccak256(abi.encodePacked(name)), addr);
    }

    function getAddress(
        uint256 chainId,
        string calldata name
    ) external view returns (address) {
        return registry[chainId][keccak256(abi.encodePacked(name))];
    }

    function getDestinationChainSelector(
        uint256 chainId
    ) external view returns (uint64) {
        return destinationChainSelector[chainId];
    }

    function getCrossChainAddress(
        uint64 destinationChainSelector_,
        string calldata name
    ) external view returns (address) {
        return
            crossChainRegistry[destinationChainSelector_][
                keccak256(abi.encodePacked(name))
            ];
    }

    function hasAddress(
        uint256 chainId,
        string calldata name
    ) external view returns (bool) {
        return
            registry[chainId][keccak256(abi.encodePacked(name))] != address(0);
    }
}
