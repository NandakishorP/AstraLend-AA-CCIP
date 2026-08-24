pragma solidity ^0.8.20;

interface ILoanController {
    function borrowLoanController(
        address user,
        address tokenAddress,
        uint256 collateralChainId,
        uint64 tokenId,
        uint256 amount
    ) external payable;

    function repayLoanController(
        address user,
        address tokenAddress,
        uint256 loanChainId,
        uint64 tokenId,
        uint256 amount,
        uint256 loanId
    ) external payable;
}
