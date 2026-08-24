pragma solidity ^0.8.20;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LoanManager is Ownable {
    constructor() Ownable(msg.sender) {}

    struct LoanDetails {
        address token;
        uint256 amountBorrowedInUSDT;
        uint256 principalAmount;
        uint256 collateralUsed;
        uint256 collateralChainId;
        uint256 lastUpdate;
        address asset;
        uint256 userBorrowIndex;
        uint256 interestPaid;
        uint256 liquidationPoint;
        uint256 loanChainId;
        uint256 dueDate;
        bool isClosed;
        uint256 loanId;
        uint8 penaltyCount;
        bool isLiquidated;
    }
    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => mapping(uint256 loanId => LoanDetails))))
        private s_loanDetails;

    mapping(uint256 chainId => mapping(address user => mapping(uint64 tokenId => uint256 totalNumberOfLoanTaken)))
        private s_numberOfLoansTaken;

    mapping(address user => mapping(uint64 tokenId => bool))
        private s_isBorrower;

    mapping(uint64 tokenId => uint256 amount) private s_totalBorrowedPerToken;


    mapping(address user => uint64[] tokens) private s_loanTokensForTheUser;

    mapping(address user => uint256[] chainId) private s_chainsUserTakeLoanFrom;

    address[] private borrowers;

    /// @notice Guards against the same borrower being appended twice.
    mapping(address user => bool registered) private s_isRegisteredBorrower;

    function getLengthOfBorrowerArray() external view returns (uint256) {
        return borrowers.length;
    }

    function getBorrower(uint256 id) external view returns (address) {
        return borrowers[id];
    }

    function getLoanTokensForTheUser(
        address user
    ) external view returns (uint64[] memory) {
        return s_loanTokensForTheUser[user];
    }

    function getLoanChainsForTheUser(
        address user
    ) external view returns (uint256[] memory) {
        return s_chainsUserTakeLoanFrom[user];
    }

    function updateLoanDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId,
        LoanDetails memory loanDetails
    ) external onlyOwner {
        bool chainExists = false;
        uint256[] storage chains = s_chainsUserTakeLoanFrom[user];
        for (uint256 i = 0; i < chains.length; i++) {
            if (chains[i] == chainId) {
                chainExists = true;
                break;
            }
        }
        if (!chainExists) {
            chains.push(chainId);
        }

        bool tokenExists = false;
        uint64[] storage tokens = s_loanTokensForTheUser[user];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == tokenId) {
                tokenExists = true;
                break;
            }
        }
        if (!tokenExists) {
            tokens.push(tokenId);
        }

        // Register the borrower for keeper scans. `borrowers` is what
        // GlobalStateManager.checkUpkeep iterates; nothing ever appended to it,
        // so the liquidation keeper always saw an empty set and no overdue loan
        // was ever discoverable.
        if (!s_isRegisteredBorrower[user]) {
            s_isRegisteredBorrower[user] = true;
            borrowers.push(user);
        }

        s_loanDetails[chainId][user][tokenId][loanId] = loanDetails;
    }

    function updateAddBorrowedPerToken(
        uint64 tokenId,
        uint256 amount
    ) external onlyOwner {
        s_totalBorrowedPerToken[tokenId] += amount;
    }

    function updateRemoveBorrowedPerToken(
        uint64 tokenId,
        uint256 amount
    ) external onlyOwner {
        s_totalBorrowedPerToken[tokenId] -= amount;
    }

    function readTotalBorrwedPerToken(
        uint64 tokenId
    ) external view onlyOwner returns (uint256) {
        return s_totalBorrowedPerToken[tokenId];
    }


    function updateLoanTakers(
        address user,
        uint64 tokenId,
        bool status
    ) external onlyOwner {
        s_isBorrower[user][tokenId] = status;
    }


    function updateNumberOfLoansTaken(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanNumber
    ) external onlyOwner {
        s_numberOfLoansTaken[chainId][user][tokenId] = loanNumber;
    }


    function getLoanDetailsOfUser(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId
    ) external view onlyOwner returns (LoanDetails memory) {
        return s_loanDetails[chainId][user][tokenId][loanId];
    }


    function getNumberOfLoansTakenPerToken(
        uint256 chainId,
        address user,
        uint64 tokenId
    ) external view onlyOwner returns (uint256) {
        return s_numberOfLoansTaken[chainId][user][tokenId];
    }

    function deleteLoanDetails(
        uint256 chainId,
        address user,
        uint64 tokenId,
        uint256 loanId
    ) external onlyOwner {
        delete s_loanDetails[chainId][user][tokenId][loanId];
    }
}
