pragma solidity ^0.8.20;
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {LendingPoolContract} from "../LendingPoolContract.sol";
pragma solidity ^0.8.20;
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {LendingPoolContract} from "../LendingPoolContract.sol";
import {IGlobalStateManager} from "../interfaces/IGlobalStateManager.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {ILendingPoolContract} from "../interfaces/ILendingPoolContract.sol";
import {ICrossChainMessageSender} from "./interfaces/ICrossChainMessageSender.sol";
import {ICCIPRequestHandler} from "./interfaces/ICCIPRequestHandler.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";
import {LoanManager} from "../GSM/LoanManager.sol";

contract CCIPRequestHandler is ICCIPRequestHandler, Ownable {
    IGlobalStateManager GSM;

    IRegistry registry;

    uint256 ethChainId = 11155111;

    ICrossChainMessageSender crossChainMessageSender;

    ILendingPoolContract lendingPoolContract;

    error OnlyOwnerCanCall();
    error InvalidChain__OnlyEthSupported();

    constructor(
        address lendingPoolContract_,
        address registry_,
        address gsm_,
        address crossChainMessageSender_
    ) Ownable(msg.sender) {
        GSM = IGlobalStateManager(gsm_);
        registry = IRegistry(registry_);

        crossChainMessageSender = ICrossChainMessageSender(
            crossChainMessageSender_
        );

        lendingPoolContract = ILendingPoolContract(lendingPoolContract_);
    }

    function setGSMAddress(address gsm) external onlyOwner {
        if (block.chainid != ethChainId) {
            revert InvalidChain__OnlyEthSupported();
        }
        GSM = IGlobalStateManager(gsm);
    }

    function updateDepositCollateralDetailsOfUser(
        LendingPoolContract.CrossChainPayLoad memory actionPayLoad
    ) external {
        GSM.updateDepositCollateralOfUser(
            actionPayLoad.chainId,
            actionPayLoad.user,
            actionPayLoad.crossChaintokenId,
            actionPayLoad.amountToTransfer
        );
    }

    function updateWithdrawDepositCollateralDetailsOfUser(
        LendingPoolContract.CrossChainPayLoad memory actionPayLoad
    ) external {
        GSM.updateWithdrawCollateralOfUser(
            actionPayLoad.chainId,
            actionPayLoad.user,
            actionPayLoad.crossChaintokenId,
            actionPayLoad.amountToTransfer
        );
    }

    function updateCollateralStateMirror(
        address receiver,
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint64 destinationChainSelector
    ) external {
        GSM.mirrorUpdateOfTheUserCollateral(
            receiver,
            chainId,
            user,
            tokenId,
            destinationChainSelector
        );
    }

    function updateBorrowLoanDetailsOfUser(
        LendingPoolContract.CrossChainPayLoad memory actionPayLoad
    ) external {
        GSM.updateBorrowLoanDetailsOfUser(
            actionPayLoad.chainId,
            actionPayLoad.user,
            actionPayLoad.crossChaintokenId,
            abi.decode(
                actionPayLoad.extraInformation,
                (LoanManager.LoanDetails)
            )
        );
    }

    function repayLoanDetailsOfUser(
        LendingPoolContract.CrossChainPayLoad memory actionPayLoad
    ) external {
        GSM.repayLoanDetailsOfUser(
            abi
                .decode(
                    actionPayLoad.extraInformation,
                    (LoanManager.LoanDetails)
                )
                .loanChainId,
            actionPayLoad.user,
            actionPayLoad.crossChaintokenId,
            abi.decode(
                actionPayLoad.extraInformation,
                (LoanManager.LoanDetails)
            )
        );
    }

    function updateLoanStateMirror(
        address receiver,
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId,
        uint64 destinationChainSelector
    ) external {
        GSM.mirrorUpdateOfTheUserLoan(
            receiver,
            chainId,
            user,
            tokenId,
            loanId,
            destinationChainSelector
        );
    }

    function updateDepositDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external {
        GSM.updateDepositDetailsOfUser(chainId, user, tokenId, amount);
    }

    function mirrorUpdateOfTheUserDeposit(
        address receiver,
        uint256 chainId_,
        address user_,
        uint64 tokenId,
        uint64 destinationChainSelector
    ) external {
        GSM.mirrorUpdateOfTheUserDeposit(
            receiver,
            chainId_,
            user_,
            tokenId,
            destinationChainSelector
        );
    }

    function updateLPTokensInCirculation(
        uint256 chainId,
        address user,
        uint256 amount
    ) external {
        GSM.updateLPTokenInCirculation(chainId, user, amount);
    }


    function updateWithdrawDepositDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external {
        GSM.updateWithDrawDetailsOfUser(chainId, user, tokenId, amount);
    }

    /**
     * @notice Overrides the chain ids this contract treats as the hub.
     *
     * The ids default to the live testnet values, so existing deployments and
     * the integration tests are unaffected. A local deployment calls this to run
     * the hub on an id that does not collide with a wallet's built-in networks —
     * MetaMask reserves 11155111 for its own Sepolia and will not let a custom
     * RPC own it, which makes gas estimation resolve against the wrong chain.
     */
    function setChainIds(uint256 ethChainId_) external onlyOwner {
        ethChainId = ethChainId_;
    }
}
