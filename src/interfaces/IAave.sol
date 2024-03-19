// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

interface IAToken {
    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

    function scaledBalanceOf(address user) external view returns (uint256);
}

interface IDataProvider {
    function getReserveTokensAddresses(address asset) external view returns (address, address, address);
}

interface ILendingPoolV3 {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    function withdraw(address asset, uint256 amount, address to) external;

    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;

    function getUserAccountData(address user) external view returns (uint256 totalCollateralBase, uint256 totalDebtBase, uint256 availableBorrowsBase, uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor);

    function getReserveNormalizedIncome(address token) external view returns (uint256);
}

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}

interface IWETHGateway {
    function depositETH(address lendingPool, address onBehalfOf, uint16 referralCode) external payable;

    function withdrawETH(address lendingPool, uint256 amount, address to) external;
}
