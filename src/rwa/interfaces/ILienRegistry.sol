// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ILienRegistry
 * @notice The public register of security interests.
 * @dev Publicity is the point. Under the Depositories Act 1996 s.12 a pledge of
 *      dematerialised securities is *recorded* rather than possessed, and it is
 *      the record that makes the charge good against third parties. LienCreated
 *      is that record's on-chain half.
 */
interface ILienRegistry {
    struct Lien {
        address borrower;
        address token;
        uint256 amount;
        bytes32 loanRef;
        uint64 perfectedAt;
        uint64 releasedAt;
        bool foreclosed;
    }

    function createLien(address borrower, address token, uint256 amount, bytes32 loanRef)
        external
        returns (bytes32 lienId);

    function increaseLien(bytes32 lienId, uint256 amount) external;

    function decreaseLien(bytes32 lienId, uint256 amount) external;

    function releaseLien(bytes32 lienId) external;

    function computeLienId(address borrower, address token, bytes32 loanRef) external pure returns (bytes32);

    function getLien(bytes32 lienId) external view returns (Lien memory);

    function isActive(bytes32 lienId) external view returns (bool);

    function totalEncumberedBy(address borrower, address token) external view returns (uint256);
}
