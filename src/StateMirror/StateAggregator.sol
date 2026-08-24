pragma solidity ^0.8.20;

import {CollateralStateMirror} from "./CollateralStateMirror.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";
import {LoanManager} from "../GSM/LoanManager.sol";
import {LoanStateMirror} from "./LoanStateMirror.sol";
import {DepositStateMirror} from "./DepositStateMirror.sol";
import {LPTokenStateMirror} from "./LPTokenStateMirror.sol";

contract StateAggregator is Ownable {
    error StateAggregator__InvalidSender();
    CollateralStateMirror collateralStateMirror;
    LoanStateMirror loanStateMirror;
    DepositStateMirror depositStateMirror;
    LPTokenStateMirror lpTokenStateMirror;
    mapping(address => bool) private s_isAuthorizedToUpdate;
    mapping(address => bool) private s_isAuthorizedToRead;
    mapping(uint64 tokenId => uint256 amount) private s_borrowerIndex;
    modifier onlyCCIPHandlersCanCall() {
        if (!s_isAuthorizedToUpdate[msg.sender]) {
            revert StateAggregator__InvalidSender();
        }
        _;
    }
    modifier onlyAuthorizedReadersCanCall() {
        if (!s_isAuthorizedToRead[msg.sender]) {
            revert StateAggregator__InvalidSender();
        }
        _;
    }

    constructor() Ownable(msg.sender) {
        collateralStateMirror = new CollateralStateMirror();
        loanStateMirror = new LoanStateMirror();
        depositStateMirror = new DepositStateMirror();
        lpTokenStateMirror = new LPTokenStateMirror();
    }

    function setAuthorizedUpdators(
        address caller,
        bool status
    ) external onlyOwner {
        s_isAuthorizedToUpdate[caller] = status;
    }
    function setAuthorizedReadors(
        address caller,
        bool status
    ) external onlyOwner {
        s_isAuthorizedToRead[caller] = status;
    }
    function updateBorrowerIndex(
        uint64 tokenId,
        uint256 value
    ) external onlyCCIPHandlersCanCall {
        s_borrowerIndex[tokenId] = value;
    }

    function getBorrowerIndex(uint64 tokenId) external view returns (uint256) {
        return s_borrowerIndex[tokenId];
    }

    function updateCollateralDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        CollateralStateMirror.CollateralDetailsOfUser
            memory collateralDetailsOfUser_
    ) external onlyCCIPHandlersCanCall {
        collateralStateMirror.updateCollateralDetaiilsOfUser(
            chainId,
            user,
            tokenId,
            collateralDetailsOfUser_
        );
    }
    function readCollateralDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view onlyAuthorizedReadersCanCall returns (uint256) {
        return
            collateralStateMirror
                .readCollateralDetailsOfUser(chainId, user, tokenId)
                .amount;
    }

    function updateLoanDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId,
        LoanManager.LoanDetails memory loanDetails
    ) external onlyCCIPHandlersCanCall {
        loanStateMirror.updateLoanDetailsOfUser(
            chainId,
            user,
            tokenId,
            loanId,
            loanDetails
        );
        loanStateMirror.updateNumberOfLoansTaken(
            chainId,
            user,
            tokenId,
            loanId
        );
    }
    function readNumberOfLoanTakenPerToken(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256) {
        return
            loanStateMirror.getNumberOfLoansTakenPerToken(
                chainId,
                user,
                tokenId
            );
    }
    function readLoanDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId
    )
        external
        view
        onlyAuthorizedReadersCanCall
        returns (LoanManager.LoanDetails memory)
    {
        return
            loanStateMirror.getLoanDetailsOfUser(
                chainId,
                user,
                tokenId,
                loanId
            );
    }
    function updateLoanTakers(
        address user,
        uint64 tokenId,
        bool status
    ) external onlyCCIPHandlersCanCall {
        loanStateMirror.updateLoanTakers(user, tokenId, status);
    }
    function getLoanTakerStatus(
        address user,
        uint64 tokenId
    ) external view onlyAuthorizedReadersCanCall returns (bool) {
        return loanStateMirror.getLoanStatusOfUserInAToken(user, tokenId);
    }
    function updateDepositDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 amount
    ) external onlyCCIPHandlersCanCall {
        depositStateMirror.updateDepositDetailsOfUser(
            chainId,
            user,
            tokenId,
            amount
        );
    }
    function readDepositDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view returns (uint256) {
        return
            depositStateMirror.readDepositDetailsOfUser(chainId, user, tokenId);
    }
    function readTotalLiquidityPerChainPerToken(
        uint256 chainId,
        uint64 tokenId
    ) external view returns (uint256) {
        return
            depositStateMirror.readTotalLiquidityPerChainPerToken(
                chainId,
                tokenId
            );
    }
    function readTotalLiquidityPerToken(
        uint64 tokenId
    ) external view returns (uint256) {
        return depositStateMirror.readTotalLiquidityPerToken(tokenId);
    }

    function updateLpTokensForAUser(address user, uint256 amount) external {
        lpTokenStateMirror.updateLpTokensForAUser(user, amount);
    }
    function getLpTokensPerUser(address user) external view returns (uint256) {
        return lpTokenStateMirror.getLpTokensPerUser(user);
    }
    function getLpTokensPerUserPerChain(
        uint64 chainId,
        address user
    ) external view returns (uint256) {
        return lpTokenStateMirror.getLpTokensPerUserPerChain(chainId, user);
    }
    function updateLpTokensPerUserPerChain(
        uint256 chainId,
        address user,
        uint256 amount
    ) external {
        lpTokenStateMirror.updateLpTokensPerUserPerChain(chainId, user, amount);
    }
    function updateTotalLpTokensInAChain(
        uint256 chainId,
        uint256 amount
    ) external {
        lpTokenStateMirror.updateTotalLpTokensInAChain(chainId, amount);
    }

    function updateLpTokenInCirculation(uint256 amount) external {
        lpTokenStateMirror.updateLpTokenInCirculation(amount);
    }

    function getTotalLpTokensInAChain(
        uint64 chainId
    ) external view returns (uint256) {
        return lpTokenStateMirror.getTotalLpTokensInAChain(chainId);
    }
    function getTotalLpTokensInCirculation() external view returns (uint256) {
        return lpTokenStateMirror.getTotalLpTokensInCirculation();
    }
    function totalLPTokensInCirculation() external view returns (uint256) {
        return lpTokenStateMirror.totalLPTokensInCirculation();
    }

    /**
     * @notice Forwards the configured chain ids to the LP token mirror.
     *
     * The mirror uses those ids as *mapping keys* when totalling LP supply
     * across chains, so a stale id reads a zeroed slot rather than reverting.
     * The aggregator owns the mirror, so the call has to go through here.
     */
    function setChainIds(uint256 ethChainId_, uint256 arbChainId_) external onlyOwner {
        lpTokenStateMirror.setChainIds(ethChainId_, arbChainId_);
    }
}
