pragma solidity ^0.8.20;

interface ICollateralController {
    function depositCollateral(
        address tokenAddress,
        uint64 tokenId,
        address sender,
        uint256 amount
    ) external payable;

    function withDrawCollateralController(
        address user,
        address tokenAddress,
        uint64 tokenId,
        uint256 amount
    ) external payable;

    function depositRwaCollateral(
        address tokenAddress,
        uint64 tokenId,
        address sender,
        uint256 amount
    ) external payable;

    function releaseRwaCollateral(address tokenAddress, address user, uint256 amount) external;

    function setLienRegistry(address lienRegistry_) external;
}
