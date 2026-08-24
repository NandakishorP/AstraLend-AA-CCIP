pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IGlobalStateManager} from "../interfaces/IGlobalStateManager.sol";
import {ILendingPoolContract} from "../interfaces/ILendingPoolContract.sol";
import {LendingPoolContract} from "../LendingPoolContract.sol";
import {ICrossChainMessageSender} from "../ccip/interfaces/ICrossChainMessageSender.sol";
import {CollateralControllerErrors} from "../errors/Errors.sol";
import {IStateAggregator} from "../interfaces/IStateAggregator.sol";
import {ICollateralController} from "./interfaces/ICollateralController.sol";
import {ILienRegistry} from "../rwa/interfaces/ILienRegistry.sol";

contract CollateralController is Ownable, ICollateralController {
    IRegistry registry;
    IVault vault;
    ILendingPoolContract lendingPoolContract;
    IStateAggregator stateAggregator;

    IGlobalStateManager GSM;

    ILienRegistry lienRegistry;

    /**
     * @dev One evergreen charge per (borrower, asset) rather than one per
     *      deposit. The pool aggregates collateral per user and asset, so a
     *      running-account charge is the shape that matches — topping up
     *      deepens the same pledge instead of stacking new ones.
     */
    bytes32 private constant COLLATERAL_PLEDGE_REF = keccak256("ASTRALEND_COLLATERAL_PLEDGE");

    uint256 ethChainId = 11155111;

    uint256 arbChainId = 421614;

    constructor(
        address registry_,
        address vault_,
        address gsm_,
        address lendingPoolContract_,
        address stateAggregator_
    ) Ownable(msg.sender) {
        registry = IRegistry(registry_);
        vault = IVault(vault_);
        GSM = IGlobalStateManager(gsm_);
        lendingPoolContract = ILendingPoolContract(lendingPoolContract_);
        stateAggregator = IStateAggregator(stateAggregator_);
    }

    function depositCollateral(
        address tokenAddress,
        uint64 tokenId,
        address sender,
        uint256 amount
    ) external payable onlyOwner {
        uint64 ethDestinationChainSelector = registry
            .getDestinationChainSelector(ethChainId);
        vault.depositCollateral(sender, tokenAddress, amount);

        if (ethChainId == block.chainid) {
            GSM.updateDepositCollateralOfUser(
                block.chainid,
                sender,
                tokenId,
                amount
            );
            uint64 arbDestinationChainSelector = registry
                .getDestinationChainSelector(arbChainId);
            address arbCrossChainReceiverAddress = registry
                .getCrossChainAddress(
                    arbDestinationChainSelector,
                    "crossChainMessageReceiverAddress"
                );

            GSM.mirrorUpdateOfTheUserCollateral(
                arbCrossChainReceiverAddress,
                block.chainid,
                sender,
                tokenId,
                arbDestinationChainSelector
            );
        } else {
            address crossChainMessageSender = registry.getAddress(
                block.chainid,
                "crossChainMessageSenderAddress"
            );

            address receiver = registry.getCrossChainAddress(
                ethDestinationChainSelector,
                "crossChainMessageReceiverAddress"
            );

            bytes memory data = abi.encode(
                lendingPoolContract.getActionCommunicationId(),
                LendingPoolContract.CrossChainPayLoad({
                    actionType: LendingPoolContract
                        .ActionType
                        .DEPOSIT_COLLATERAL,
                    chainId: block.chainid,
                    user: sender,
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
                revert CollateralControllerErrors
                    .CollateralController__InsufficentFees();
            }

            (bool success, ) = payable(address(crossChainMessageSender)).call{
                value: fees
            }("");

            if (!success) {
                revert CollateralControllerErrors
                    .CollateralController__TransferFailed();
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

        emit LendingPoolContract.CollateralDeposited(
            sender,
            tokenAddress,
            amount
        );
    }

    /**
     * @notice Records a charge over a real-world asset instead of taking it.
     *
     * @dev The single line that separates this from `depositCollateral` above
     *      is the absence of `vault.depositCollateral`. Nothing is transferred,
     *      so no contract becomes holder of record and the borrower keeps
     *      title — which is what a pledge has always meant, and what the
     *      Depositories Act 1996 s.12 recorded pledge does for dematerialised
     *      securities in India.
     *
     *      Everything downstream is unchanged. The charge is booked into the
     *      GSM under the same collateral accounting as crypto, and mirrored to
     *      the satellite the same way, so borrowing against it cross-chain
     *      needs no new machinery at all.
     *
     *      Hub-only, enforced by the pool before this is reached: the asset
     *      exists here and nowhere else, which is exactly why only a message
     *      about it ever crosses.
     */
    function depositRwaCollateral(
        address tokenAddress,
        uint64 tokenId,
        address sender,
        uint256 amount
    ) external payable onlyOwner {
        bytes32 lienId = lienRegistry.computeLienId(sender, tokenAddress, COLLATERAL_PLEDGE_REF);

        if (lienRegistry.isActive(lienId)) {
            lienRegistry.increaseLien(lienId, amount);
        } else {
            lienRegistry.createLien(sender, tokenAddress, amount, COLLATERAL_PLEDGE_REF);
        }

        GSM.updateDepositCollateralOfUser(block.chainid, sender, tokenId, amount);

        uint64 arbDestinationChainSelector = registry.getDestinationChainSelector(arbChainId);
        address arbCrossChainReceiverAddress = registry.getCrossChainAddress(
            arbDestinationChainSelector,
            "crossChainMessageReceiverAddress"
        );

        GSM.mirrorUpdateOfTheUserCollateral(
            arbCrossChainReceiverAddress,
            block.chainid,
            sender,
            tokenId,
            arbDestinationChainSelector
        );

        emit LendingPoolContract.CollateralDeposited(sender, tokenAddress, amount);
    }

    /// @notice Partially discharges a charge when RWA collateral is withdrawn.
    function releaseRwaCollateral(
        address tokenAddress,
        address user,
        uint256 amount
    ) external onlyOwner {
        bytes32 lienId = lienRegistry.computeLienId(user, tokenAddress, COLLATERAL_PLEDGE_REF);
        lienRegistry.decreaseLien(lienId, amount);
    }

    function setLienRegistry(address lienRegistry_) external onlyOwner {
        lienRegistry = ILienRegistry(lienRegistry_);
    }

    function getLienRegistry() external view returns (address) {
        return address(lienRegistry);
    }

    function withDrawCollateralController(
        address user,
        address tokenAddress,
        uint64 tokenId,
        uint256 amount
    ) external payable {
        bool chainIdentifier = block.chainid == ethChainId;

        uint256 collateralAmount = chainIdentifier
            ? GSM.getUserCollateralDetails(block.chainid, user, tokenId)
            : stateAggregator.readCollateralDetailsOfUser(
                block.chainid,
                user,
                tokenId
            );

        if (collateralAmount < amount) {
            revert CollateralControllerErrors
                .CollateralContorller__InvalidRequestAmount();
        }

        if (chainIdentifier) {
            GSM.updateWithdrawCollateralOfUser(
                block.chainid,
                user,
                tokenId,
                amount
            );

            uint64 arbDestinationChainSelector = registry
                .getDestinationChainSelector(arbChainId);

            address arbCrossChainReceiverAddress = registry
                .getCrossChainAddress(
                    arbDestinationChainSelector,
                    "crossChainMessageReceiverAddress"
                );

            GSM.mirrorUpdateOfTheUserCollateral(
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

            bytes memory data = abi.encode(
                lendingPoolContract.getActionCommunicationId(),
                LendingPoolContract.CrossChainPayLoad({
                    actionType: LendingPoolContract
                        .ActionType
                        .WITHDRAW_COLLATERAL,
                    chainId: block.chainid,
                    user: user,
                    crossChaintokenId: tokenId,
                    amountToTransfer: amount,
                    messageToTransfer: "",
                    extraInformation: ""
                })
            );

            address crossChainMessageSender = registry.getAddress(
                block.chainid,
                "crossChainMessageSenderAddress"
            );

            uint256 fees = ICrossChainMessageSender(crossChainMessageSender)
                .getFee(
                    receiver,
                    data,
                    ethDestinationChainSelector,
                    address(0),
                    amount,
                    false
                );

            if (msg.value < fees) {
                revert CollateralControllerErrors
                    .CollateralController__InsufficentFees();
            }

            (bool success, ) = payable(address(crossChainMessageSender)).call{
                value: fees
            }("");

            if (!success) {
                revert CollateralControllerErrors
                    .CollateralController__TransferFailed();
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

        vault.transferCollateral(user, tokenAddress, amount);

        emit LendingPoolContract.CollateralWithdrawed(
            user,
            tokenAddress,
            amount
        );
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
