// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

interface IUniswapV3Pool {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function swap(address recipient, bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96, bytes calldata data) external returns (int256 amount0, int256 amount1);

    function fee() external view returns (uint24);
}
