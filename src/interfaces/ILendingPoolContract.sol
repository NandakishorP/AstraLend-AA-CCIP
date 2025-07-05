// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ILendingPoolContract {
    function getTotalLiquidityPerToken(
        uint64 tokenId
    ) external view returns (uint256);

    function getTotalBorroweedForAToken(
        uint64 tokenId
    ) external view returns (uint256);

    function getPriceFeedAddress(
        uint64 tokenId
    ) external view returns (address);

    function getTokenAddressFromTokenId(
        uint64 tokenId
    ) external view returns (address);

    function receiveTokensFromOneChainToOther(bytes memory data) external;

    function getCrossChainMessageSenderAddress()
        external
        view
        returns (address);

    function getActionCommunicationId() external pure returns (uint64);

    function getResponseCommunicationId() external pure returns (uint64);

    function getUserBalance(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256);

    function getTotalLPTokensForTheUser(
        address user
    ) external view returns (uint256);

    function getUsdValue(
        uint64 tokenId,
        uint256 amount
    ) external view returns (uint256);

    function getAmountToRepay(
        uint256 loanChainId,
        uint64 tokenId,
        uint256 loanId
    ) external returns (uint256);
}
