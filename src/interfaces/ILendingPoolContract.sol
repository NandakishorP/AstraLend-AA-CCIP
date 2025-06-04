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

    function updateCollateralDetailsCrossChain(
        bytes32 requestId,
        uint256 balance
    ) external;

    function getCrossChainMessageSenderAddress()
        external
        view
        returns (address);

    function getRequestCommunicationId() external pure returns (uint64);

    function getActionCommunicationId() external pure returns (uint64);

    function getResponseCommunicationId() external pure returns (uint64);
}
