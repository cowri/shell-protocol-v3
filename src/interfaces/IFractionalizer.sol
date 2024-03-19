// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

interface IFractionalizer {
    function getTokenSupply(uint256 tokenId) external view returns (uint256);
    function fungibleTokenId() external view returns (uint256);
    function registeredTokenNonce() external view returns (uint256);
    function fungibleTokenIds(uint256 id) external view returns (uint256);
    function exchangeRate() external view returns (uint256);
    function nftCollection() external view returns (address);
    function ocean() external view returns (address);
}
