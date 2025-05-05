// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library LendingPoolContractErrors {
    error LendingPoolContract__AmountShouldBeGreaterThanZero();
    error LendingPoolContract__TokenIsNotAllowedToDeposit(address token);
    error LendingPoolContract__TokenAddressAndPriceFeedAddressMismatch(
        uint256 tokenAddressLength,
        uint256 priceFeedAddressLength
    );
    error LendingPoolContract__InsufficentBalance(
        uint256 amount,
        uint256 availableAmount
    );
    error LendingPoolContract__LoanPending();
    error LendingPoolContract__NotEnoughCollateral();
    error LendingPoolContract__LoanAmountExceeded();
    error LendingPoolContract__InvalidRequestAmount();
    error LendingPoolContract__LoanIsNotActive();
    error LendingPoolContract__NotLiquidatable();
    error LendingPoolContract__LoanStillPending();
    error LendingPoolContract__LpTokenMintFailed();
    error LendingPoolContract__InsufficentLpTokenBalance(
        uint256 availableBalance
    );
}

library FlashLenderContractErrors {
    error FlashLenderContract__TokenNotSupported();
    error FlashLenderContract__TokenTransferFailed();
    error FlashLenderContract__WithdrawFailed();
    error FlashLenderContract__TokenRepaymentFailed();
    error FlashLenderContract__CallBackFailed();
    error FlashLenderContract__NotEnoughAllowance();
}

library InterestRateModelErrors {
    error InterestRateModel__TokenNotSupported();
    error InterestRateModel__AmountShouldBeGreaterThanZero();
}

library LpTokenErrors {
    error LpToken__AmountMustBeMoreThanZero();
    error LpToken__NotEnoughTokensToBurn(
        uint256 userBalance,
        uint256 amountProvided
    );
    error LpToken__InvalidAddress();
}

library StableCoinErrors {
    error StableCoin__AmountMustBeMoreThanZero();
    error StableCoin__NotEnoughTokensToBurn(
        uint256 userBalance,
        uint256 amountProvided
    );
    error StableCoin__InvalidAddress();
}
