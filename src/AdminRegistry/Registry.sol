// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";

contract Registry is Ownable {
    /**
     * @dev Stores contract addresses based on a chain ID and a hashed name identifier.
     * @notice Used to manage addresses relevant to a specific chain context (e.g., cross-chain receivers, oracles).
     * mapping[chainId][nameHash] => address
     */
    mapping(uint256 => mapping(bytes32 => address)) private registry;

    /**
     * @dev Stores addresses relevant for cross-chain operations using CCIP chain selectors.
     * @notice Allows lookup of contract addresses for destination chains in cross-chain messaging.
     * mapping[destinationChainSelector][nameHash] => address
     */
    mapping(uint64 destinationChainSelector => mapping(bytes32 => address))
        private crossChainRegistry;

    /**
     * @dev Maps EVM chain IDs to their corresponding CCIP destination chain selectors.
     * @notice Used to find the correct selector for a given chain ID during message construction.
     * mapping[chainId] => destinationChainSelector
     */
    mapping(uint256 chainId => uint64) private destinationChainSelector;

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Emitted when an address is set for a specific chain and name.
     * @param chainId The EVM chain ID for which the address is being registered.
     * @param name The hashed identifier for the contract/role (e.g., keccak256("oracle")).
     * @param addr The address associated with the name on the specified chain.
     */
    event AddressSet(
        uint256 indexed chainId,
        bytes32 indexed name,
        address indexed addr
    );

    /**
     * @notice Sets the destination chain selector for a given EVM chain ID.
     * @dev Stores a mapping between a chain ID and its corresponding CCIP destination chain selector.
     * This is used for cross-chain message routing via Chainlink CCIP.
     *
     * @param chainId The EVM chain ID for which the selector is being set.
     * @param destinationChainSelector_ The Chainlink CCIP destination chain selector.
     *
     * @custom:access Only callable by the contract owner.
     */

    function setDestinationChainSelector(
        uint256 chainId,
        uint64 destinationChainSelector_
    ) external onlyOwner {
        destinationChainSelector[chainId] = destinationChainSelector_;
    }

    /**
     * @notice Sets an address in the cross-chain registry for a given destination chain selector and name.
     * @dev The name is hashed using keccak256 to avoid collisions and maintain a consistent lookup structure.
     *
     * @param destinationChainSelector_ The Chainlink CCIP destination chain selector.
     * @param name The string identifier (e.g., "crossChainMessageReceiverAddress").
     * @param addr The address to be registered.
     *
     * Emits an {AddressSet} event indicating the registry update.
     *
     * @custom:access Only callable by the contract owner.
     * @custom:require The `addr` must not be the zero address.
     */

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

    /**
     * @notice Sets an address in the registry for a specific chain ID and identifier name.
     * @dev The name is hashed with `keccak256` to maintain a consistent key format.
     * This allows the protocol to store and reference cross-chain or modular addresses dynamically.
     *
     * @param chainId The EVM chain ID to associate the address with.
     * @param name The identifier name for the address (e.g., "oracle", "router").
     * @param addr The address to be registered.
     *
     * Emits an {AddressSet} event upon successful registration.
     *
     * @custom:access Only callable by the contract owner.
     * @custom:require `addr` must not be the zero address.
     */

    function setAddress(
        uint256 chainId,
        string calldata name,
        address addr
    ) external onlyOwner {
        require(addr != address(0), "Invalid address");
        registry[chainId][keccak256(abi.encodePacked(name))] = addr;
        emit AddressSet(chainId, keccak256(abi.encodePacked(name)), addr);
    }

    /**
     * @notice Retrieves an address from the registry for the given chain ID and identifier name.
     * @dev The name is hashed using `keccak256` to match the storage format used in `setAddress`.
     *
     * @param chainId The EVM chain ID associated with the address.
     * @param name The identifier name for the registered address.
     * @return The address associated with the given chain ID and name.
     */

    function getAddress(
        uint256 chainId,
        string calldata name
    ) external view returns (address) {
        return registry[chainId][keccak256(abi.encodePacked(name))];
    }

    /**
     * @notice Returns the destination chain selector associated with a specific EVM chain ID.
     * @dev Useful for cross-chain communication where selector IDs are required instead of chain IDs.
     *
     * @param chainId The EVM chain ID whose destination selector is being queried.
     * @return The corresponding destination chain selector.
     */

    function getDestinationChainSelector(
        uint256 chainId
    ) external view returns (uint64) {
        return destinationChainSelector[chainId];
    }

    /**
     * @notice Retrieves the registered cross-chain address for a given destination chain selector and identifier name.
     * @dev The `name` is hashed with `keccak256` to generate a consistent lookup key.
     *
     * @param destinationChainSelector_ The unique selector ID for the target chain.
     * @param name The identifier name used during registration (e.g., "bridgeReceiver", "messageHandler").
     * @return The address associated with the given selector and name.
     */

    function getCrossChainAddress(
        uint64 destinationChainSelector_,
        string calldata name
    ) external view returns (address) {
        return
            crossChainRegistry[destinationChainSelector_][
                keccak256(abi.encodePacked(name))
            ];
    }

    /**
     * @notice Checks whether an address is registered for a given chain ID and name.
     * @dev The `name` is encoded and hashed using `keccak256` for consistent key mapping.
     *
     * @param chainId The target chain ID to check against.
     * @param name The identifier name associated with the address (e.g., "bridgeReceiver", "oracle").
     * @return True if an address is registered under the given chain ID and name; false otherwise.
     */

    function hasAddress(
        uint256 chainId,
        string calldata name
    ) external view returns (bool) {
        return
            registry[chainId][keccak256(abi.encodePacked(name))] != address(0);
    }
}
