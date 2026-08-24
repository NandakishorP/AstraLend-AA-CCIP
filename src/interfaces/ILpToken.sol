pragma solidity ^0.8.24;

interface ILpToken {
    function mint(address _to, uint256 _amount) external returns (bool);
    function burn(address user, uint256 _amount) external;
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}
