// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

interface IProteus {
    function ocean() external returns (address);
    function xToken() external returns (uint256);
    function yToken() external returns (uint256);
    function lpTokenId() external returns (uint256);
}
