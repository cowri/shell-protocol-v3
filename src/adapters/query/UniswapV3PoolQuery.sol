// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

import { IPoolQuery, SpecifiedToken } from "../../interfaces/IPoolQuery.sol";
import "../UniswapV3Adapter.sol";
import "../../interfaces/IQuoter.sol";

contract UniswapV3PoolQuery is IPoolQuery {
    UniswapV3Adapter public immutable adapter;
    IQuoter public immutable quoter;

    uint256 public immutable xToken;
    uint256 public immutable yToken;

    mapping(uint256 => uint8) public decimals;

    uint8 public constant NORMALIZED_DECIMALS = 18;

    constructor(address payable adapter_, IQuoter quoter_) {
        adapter = UniswapV3Adapter(adapter_);
        quoter = quoter_;

        xToken = adapter.xToken();
        yToken = adapter.yToken();

        decimals[xToken] = adapter.decimals(xToken);
        decimals[yToken] = adapter.decimals(yToken);
    }

    function swapGivenInputAmount(uint256 inputToken, uint256 inputAmount) public view returns (uint256 outputAmount) {
        uint256 rawInputAmount = _convertDecimals(NORMALIZED_DECIMALS, decimals[inputToken], inputAmount);

        bool isX = inputToken == xToken;

        IQuoter.QuoteExactInputSingleWithPoolParams memory params = IQuoter.QuoteExactInputSingleWithPoolParams({
            tokenIn: isX ? adapter.underlying(xToken) : adapter.underlying(yToken),
            tokenOut: isX ? adapter.underlying(yToken) : adapter.underlying(xToken),
            amountIn: rawInputAmount,
            pool: adapter.primitive(),
            fee: IUniswapV3Pool(adapter.primitive()).fee(),
            sqrtPriceLimitX96: 0
        });

        (uint256 amountReceived,,,) = quoter.quoteExactInputSingleWithPool(params);

        uint256 outputToken = isX ? yToken : xToken;

        outputAmount = _convertDecimals(decimals[outputToken], NORMALIZED_DECIMALS, amountReceived);
    }

    function swapGivenInputAmount(uint256 xBalance, uint256 yBalance, uint256 inputAmount, SpecifiedToken inputToken) public view returns (uint256 outputAmount) {
        bool isX = inputToken == SpecifiedToken.X;

        outputAmount = swapGivenInputAmount(isX ? xToken : yToken, inputAmount);
    }

    function depositGivenInputAmount(uint256 depositToken, uint256 depositAmount) external view override returns (uint256) { }

    function withdrawGivenInputAmount(uint256 withdrawnToken, uint256 burnAmount) external view override returns (uint256) { }

    /**
     * @dev convert a uint256 from one fixed point decimal basis to another,
     *   returning the truncated amount if a truncation occurs.
     * @dev fn(from, to, a) => b
     * @dev a = (x * 10**from) => b = (x * 10**to), where x is constant.
     * @param amountToConvert the amount being converted
     * @param decimalsFrom the fixed decimal basis of amountToConvert
     * @param decimalsTo the fixed decimal basis of the returned convertedAmount
     * @return convertedAmount the amount after conversion
     */
    function _convertDecimals(uint8 decimalsFrom, uint8 decimalsTo, uint256 amountToConvert) internal pure returns (uint256 convertedAmount) {
        if (decimalsFrom == decimalsTo) {
            // no shift
            convertedAmount = amountToConvert;
        } else if (decimalsFrom < decimalsTo) {
            // Decimal shift left (add precision)
            uint256 shift = 10 ** (uint256(decimalsTo - decimalsFrom));
            convertedAmount = amountToConvert * shift;
        } else {
            // Decimal shift right (remove precision) -> truncation
            uint256 shift = 10 ** (uint256(decimalsFrom - decimalsTo));
            convertedAmount = amountToConvert / shift;
        }
    }
}
