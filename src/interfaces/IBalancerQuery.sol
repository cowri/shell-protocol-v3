// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

import { IBalancerVault } from "./IBalancerVault.sol";

interface IBalancerQuery {
    function _onRegularSwap(bool isGivenIn, uint256 amountGiven, uint256[] memory registeredBalances, uint256 registeredIndexIn, uint256 registeredIndexOut, uint256 currentAmp) external view returns (uint256);

    function _joinSwapExactTokenInForBptOut(uint256 amountIn, uint256[] memory balances, uint256 indexIn, uint256 currentAmp, uint256 actualSupply, uint256 preJoinExitInvariant) external view returns (uint256, uint256);

    function _exitSwapExactBptInForTokenOut(uint256 bptAmount, uint256[] memory balances, uint256 indexOut, uint256 currentAmp, uint256 actualSupply, uint256 preJoinExitInvariant) external view returns (uint256, uint256);

    function getAmplificationParameter() external view returns (uint256 value, bool isUpdating, uint256 precision);

    function getScalingFactors() external view returns (uint256[] memory);

    function getBptIndex() external view returns (uint256);

    function getSwapFeePercentage() external view returns (uint256);

    function getActualSupply() external view returns (uint256);
}
