// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

interface IUniswapV2Router {
    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] memory path, address to, uint256 deadline) external returns (uint256[] memory);
}
