pragma solidity ^0.8.20;

interface IRegistry {
    function setAddress(
        uint256 chainId,
        string calldata name,
        address addr
    ) external;

    function getAddress(
        uint256 chainId,
        string calldata name
    ) external view returns (address);

    function hasAddress(
        uint256 chainId,
        string calldata name
    ) external view returns (bool);

    function getCrossChainAddress(
        uint64 destinationChainSelector,
        string calldata name
    ) external view returns (address);

    function setCrossChainRegistryAddress(
        uint64 destinationChainSelector,
        string calldata name,
        address addr
    ) external;

    function getDestinationChainSelector(
        uint256 chainId
    ) external view returns (uint64);
}
