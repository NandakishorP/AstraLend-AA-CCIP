pragma solidity ^0.8.24;

interface ICrossChainMessageSender {
    function sendViaNativeToken(
        address receiver,
        bytes memory _data,
        uint64 destinationChainSelector,
        address _token,
        uint256 _amount
    ) external returns (bytes32 messageId);

    function getFee(
        address receiver,
        bytes memory _data,
        uint64 destinationChainSelector,
        address _token,
        uint256 _amount,
        bool isLink
    ) external view returns (uint256 fees);

    function sendViaLink(
        address receiver,
        bytes memory _data,
        uint64 destinationChainSelector,
        address _token,
        uint256 _amount
    ) external returns (bytes32 messageId);

    function setAllowedCallers(address sender, bool status) external;
}
