pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {ILendingPoolContract} from "../interfaces/ILendingPoolContract.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IGlobalStateManager} from "../interfaces/IGlobalStateManager.sol";
import {IStateAggregator} from "../interfaces/IStateAggregator.sol";
import {ILpToken} from "../interfaces/ILpToken.sol";
import {LiquidityControllerErrors} from "../errors/Errors.sol";
import {LendingPoolContract} from "../LendingPoolContract.sol";
import {ICrossChainMessageSender} from "../ccip/interfaces/ICrossChainMessageSender.sol";
import {ILiquidityContorller} from "./interfaces/ILiquidityController.sol";

contract LiquidityController is Ownable, ILiquidityContorller {
    IRegistry registry;
    ILendingPoolContract lendingPoolContract;
    IGlobalStateManager GSM;
    IVault vault;
    uint64 ethTokenId = 0;
    IStateAggregator stateAggregator;
    ILpToken lpToken;

    uint256 ethChainId = 11155111;

    uint256 arbChainId = 421614;


    modifier isGreaterThanZero(uint256 amount) {
        if (amount == 0) {
            revert LiquidityControllerErrors
                .LiquidityController__AmountShouldBeGreaterThanZero();
        }
        _;
    }

    constructor(
        address registry_,
        address lendingPoolContract_,
        address vault_,
        address gsm_,
        address stateAggregator_,
        address lpToken_
    ) Ownable(msg.sender) {
        registry = IRegistry(registry_);
        lendingPoolContract = ILendingPoolContract(lendingPoolContract_);
        vault = IVault(vault_);
        GSM = IGlobalStateManager(gsm_);
        stateAggregator = IStateAggregator(stateAggregator_);
        lpToken = ILpToken(lpToken_);
    }

    function depositController(
        address tokenAddress,
        uint64 tokenId,
        address sender,
        uint256 amount
    ) external payable onlyOwner {
        uint64 ethDestinationChainSelector = registry
            .getDestinationChainSelector(ethChainId);
        vault.depositLiquidity(sender, tokenAddress, amount);
        uint256 currentTotalLiquidity;
        uint256 totalSupplyOfLpToken;

        if (block.chainid == ethChainId) {
            currentTotalLiquidity = GSM.readTotalLiquidityPerToken(tokenId);
            totalSupplyOfLpToken = GSM.getTotalLpTokensInCirculation();
        } else {
            currentTotalLiquidity = stateAggregator.readTotalLiquidityPerToken(
                tokenId
            );
            totalSupplyOfLpToken = stateAggregator
                .getTotalLpTokensInCirculation();
        }
        uint256 amountOfLpTokensToMint;
        if (totalSupplyOfLpToken == 0 || currentTotalLiquidity == amount) {
            if (tokenId == ethTokenId) {
                amountOfLpTokensToMint = amount;
            } else {
                uint256 ethInUsd = lendingPoolContract.getUsdValue(
                    ethTokenId,
                    1
                );

                uint256 arbInUsd = lendingPoolContract.getUsdValue(tokenId, 1);
                amountOfLpTokensToMint = (ethInUsd / arbInUsd) * (amount);
            }
        } else {
            if (tokenId == ethTokenId) {
                amountOfLpTokensToMint =
                    (amount * totalSupplyOfLpToken) /
                    currentTotalLiquidity;
            } else {
                uint256 ethInUsd = lendingPoolContract.getUsdValue(
                    ethTokenId,
                    1
                );

                uint256 arbInUsd = lendingPoolContract.getUsdValue(tokenId, 1);

                amountOfLpTokensToMint =
                    (ethInUsd / arbInUsd) *
                    ((amount * totalSupplyOfLpToken) / currentTotalLiquidity);
            }
        }
        _mintLpTokens(sender, amountOfLpTokensToMint);
        if (block.chainid == ethChainId) {
            GSM.updateDepositDetailsOfUser(
                block.chainid,
                sender,
                tokenId,
                amount
            );
            GSM.updateLPTokenInCirculation(
                block.chainid,
                sender,
                amountOfLpTokensToMint
            );
            uint64 arbDestinationChainSelector = registry
                .getDestinationChainSelector(arbChainId);
            address arbCrossChainReceiverAddress = registry
                .getCrossChainAddress(
                    arbDestinationChainSelector,
                    "crossChainMessageReceiverAddress"
                );

            GSM.mirrorUpdateOfTheUserDeposit(
                arbCrossChainReceiverAddress,
                block.chainid,
                sender,
                tokenId,
                arbDestinationChainSelector
            );
        } else {
            address receiver = registry.getCrossChainAddress(
                ethDestinationChainSelector,
                "crossChainMessageReceiverAddress"
            );

            address crossChainMessageSender = registry.getAddress(
                block.chainid,
                "crossChainMessageSenderAddress"
            );
            bytes memory data = abi.encode(
                lendingPoolContract.getActionCommunicationId(),
                LendingPoolContract.CrossChainPayLoad({
                    actionType: LendingPoolContract
                        .ActionType
                        .DEPOSIT_LIQUIDITY,
                    chainId: block.chainid,
                    user: sender,
                    crossChaintokenId: tokenId,
                    amountToTransfer: amount,
                    messageToTransfer: "",
                    extraInformation: abi.encode(amountOfLpTokensToMint)
                })
            );
            uint256 fees = ICrossChainMessageSender(crossChainMessageSender)
                .getFee(
                    receiver,
                    data,
                    ethDestinationChainSelector,
                    address(0),
                    0,
                    false
                );
            if (msg.value < fees) {
                revert LiquidityControllerErrors
                    .LiquidityController__InsufficentFees();
            }
            (bool success, ) = payable(address(crossChainMessageSender)).call{
                value: fees
            }("");
            if (!success) {
                revert LiquidityControllerErrors
                    .LiquidityController__TransferFailed();
            }
            ICrossChainMessageSender(crossChainMessageSender)
                .sendViaNativeToken(
                    receiver,
                    data,
                    ethDestinationChainSelector,
                    address(0),
                    amount
                );
        }
        emit LendingPoolContract.LiquidityDeposited(
            sender,
            tokenAddress,
            amount,
            amountOfLpTokensToMint
        );
    }

    function _mintLpTokens(
        address to,
        uint256 amountToMint
    ) internal isGreaterThanZero(amountToMint) {
        if (!lpToken.mint(to, amountToMint)) {
            revert LiquidityControllerErrors
                .LiquidityController__LpTokenMintFailed();
        }
    }
    function withDrawController(
        address tokenAddress,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external payable onlyOwner {
        uint256 depositAmount = block.chainid == ethChainId
            ? GSM.readDepositDetailsOfUser(block.chainid, user, tokenId)
            : stateAggregator.readDepositDetailsOfUser(
                block.chainid,
                user,
                tokenId
            );
        if (depositAmount < amount) {
            revert LiquidityControllerErrors
                .LiquidityController__InsufficentFees();
        }
        uint256 balanceAmount = depositAmount - amount;
        if (block.chainid == ethChainId) {
            GSM.updateWithDrawDetailsOfUser(
                block.chainid,
                user,
                tokenId,
                balanceAmount
            );
            uint64 arbDestinationChainSelector = registry
                .getDestinationChainSelector(arbChainId);
            address arbCrossChainReceiverAddress = registry
                .getCrossChainAddress(
                    arbDestinationChainSelector,
                    "crossChainMessageReceiverAddress"
                );
            GSM.mirrorUpdateOfTheUserDeposit(
                arbCrossChainReceiverAddress,
                block.chainid,
                user,
                tokenId,
                arbDestinationChainSelector
            );
        } else {
            uint64 ethDestinationChainSelector = registry
                .getDestinationChainSelector(ethChainId);
            address receiver = registry.getCrossChainAddress(
                ethDestinationChainSelector,
                "crossChainMessageReceiverAddress"
            );
            address crossChainMessageSender = registry.getAddress(
                block.chainid,
                "crossChainMessageSenderAddress"
            );
            bytes memory data = abi.encode(
                lendingPoolContract.getActionCommunicationId(),
                LendingPoolContract.CrossChainPayLoad({
                    actionType: LendingPoolContract
                        .ActionType
                        .WITHDRAW_LIQUIDITY,
                    chainId: block.chainid,
                    user: user,
                    crossChaintokenId: tokenId,
                    amountToTransfer: amount,
                    messageToTransfer: "",
                    extraInformation: ""
                })
            );
            uint256 fees = ICrossChainMessageSender(crossChainMessageSender)
                .getFee(
                    receiver,
                    data,
                    ethDestinationChainSelector,
                    address(0),
                    0,
                    false
                );
            if (msg.value < fees) {
                revert LiquidityControllerErrors
                    .LiquidityController__InsufficentFees();
            }
            (bool success, ) = payable(address(crossChainMessageSender)).call{
                value: fees
            }("");
            if (!success) {
                revert LiquidityControllerErrors
                    .LiquidityController__TransferFailed();
            }
            ICrossChainMessageSender(crossChainMessageSender)
                .sendViaNativeToken(
                    receiver,
                    data,
                    ethDestinationChainSelector,
                    address(0),
                    amount
                );
        }
        vault.withdrawDeposit(user, tokenAddress, amount);
        emit LendingPoolContract.DepositWithdrawn(user, tokenAddress, amount);
    }

    /**
     * @notice Overrides the chain ids this contract treats as hub and satellite.
     *
     * The ids default to the live testnet values, so existing deployments and
     * the integration tests are unaffected. A local deployment calls this to run
     * the hub on an id that does not collide with a wallet's built-in networks —
     * MetaMask reserves 11155111 for its own Sepolia and will not let a custom
     * RPC own it, which makes gas estimation resolve against the wrong chain.
     */
    function setChainIds(uint256 ethChainId_, uint256 arbChainId_) external onlyOwner {
        ethChainId = ethChainId_;
        arbChainId = arbChainId_;
    }
}
