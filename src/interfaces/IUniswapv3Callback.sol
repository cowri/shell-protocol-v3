// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

interface IUniswapv3Callback {
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}
