// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

enum SpecifiedToken {
    X,
    Y
}

interface IPoolQuery {
    function swapGivenInputAmount(uint256 inputToken, uint256 inputAmount) external view returns (uint256);
    function depositGivenInputAmount(uint256 depositToken, uint256 depositAmount) external view returns (uint256);
    function withdrawGivenInputAmount(uint256 withdrawnToken, uint256 burnAmount) external view returns (uint256);
}
