// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

import { IPoolQuery, SpecifiedToken } from "../../interfaces/IPoolQuery.sol";
import "../../interfaces/IBalancerQuery.sol";
import "../BalancerAdapter.sol";

contract BalancerVolatilePoolQuery is IPoolQuery {
    uint8 public constant NORMALIZED_DECIMALS = 18;

    BalancerAdapter immutable adapter;
    IBalancerQuery immutable poolQuery;
    IPool immutable pool;

    uint256 public immutable xToken; // weth
    uint256 public immutable yToken; // reth
    uint256 public immutable lpTokenId;

    uint256 public immutable numAssets;

    mapping(uint256 => uint8) public decimals;

    mapping(uint256 => uint256) public indexOf;

    constructor(address payable adapter_, address query_) {
        adapter = BalancerAdapter(adapter_);
        poolQuery = IBalancerQuery(query_);

        pool = adapter.pool();

        xToken = adapter.xToken();
        yToken = adapter.yToken();
        lpTokenId = adapter.lpTokenId();

        decimals[xToken] = adapter.decimals(xToken);
        decimals[yToken] = adapter.decimals(yToken);
        decimals[lpTokenId] = adapter.decimals(lpTokenId);

        (IERC20[] memory tokens,,) = IBalancerVault(adapter.primitive()).getPoolTokens(pool.getPoolId());
        numAssets = tokens.length;

        uint256 bptIndex = poolQuery.getBptIndex();
        if (bptIndex == 0) {
            indexOf[xToken] = 1;
            indexOf[yToken] = 2;
        } else if (bptIndex == 1) {
            indexOf[xToken] = 0;
            indexOf[yToken] = 2;
        } else {
            indexOf[xToken] = 0;
            indexOf[yToken] = 1;
        }
    }

    function swapGivenInputAmount(uint256 inputToken, uint256 inputAmount) external view override returns (uint256) { }
    function depositGivenInputAmount(uint256 depositToken, uint256 depositAmount) external view override returns (uint256) { }
    function withdrawGivenInputAmount(uint256 withdrawnToken, uint256 burnAmount) external view override returns (uint256) { }

    function swapGivenInputAmount(uint256 xBalance, uint256 yBalance, uint256 inputAmount, SpecifiedToken inputToken) public view returns (uint256 outputAmount) {
        bool isX = inputToken == SpecifiedToken.X;

        uint256 rawInputAmount = _convertDecimals(NORMALIZED_DECIMALS, decimals[isX ? xToken : yToken], inputAmount);

        uint256 rawXBalance = _convertDecimals(NORMALIZED_DECIMALS, decimals[xToken], xBalance);
        uint256 rawYBalance = _convertDecimals(NORMALIZED_DECIMALS, decimals[yToken], yBalance);

        (uint256 amplification,,) = pool.getAmplificationParameter();

        uint256[] memory balances = new uint256[](numAssets);
        balances[indexOf[xToken]] = rawXBalance;
        balances[indexOf[yToken]] = rawYBalance;
        balances[poolQuery.getBptIndex()] = 1e18;

        uint256[] memory scalingFactors = poolQuery.getScalingFactors();
        _upscaleArray(balances, scalingFactors);

        uint256 rawOutputAmount =
            poolQuery._onRegularSwap(true, mulDown(rawInputAmount, scalingFactors[isX ? indexOf[xToken] : indexOf[yToken]]), balances, isX ? indexOf[xToken] : indexOf[yToken], isX ? indexOf[yToken] : indexOf[xToken], amplification);

        uint256 feeAmount = mulUp(rawOutputAmount, poolQuery.getSwapFeePercentage());
        rawOutputAmount = rawOutputAmount - feeAmount;

        rawOutputAmount = divDown(rawOutputAmount, scalingFactors[isX ? indexOf[yToken] : indexOf[xToken]]);

        uint256 outputToken = isX ? yToken : xToken;

        outputAmount = _convertDecimals(decimals[outputToken], NORMALIZED_DECIMALS, rawOutputAmount);
    }

    function depositGivenInputAmount(uint256 xBalance, uint256 yBalance, uint256 totalSupply, uint256 depositAmount, SpecifiedToken depositToken) public view returns (uint256 mintAmount) {
        bool isX = depositToken == SpecifiedToken.X;

        uint256 rawInputAmount = _convertDecimals(NORMALIZED_DECIMALS, decimals[isX ? xToken : yToken], depositAmount);

        uint256 rawXBalance = _convertDecimals(NORMALIZED_DECIMALS, decimals[xToken], xBalance);
        uint256 rawYBalance = _convertDecimals(NORMALIZED_DECIMALS, decimals[yToken], yBalance);
        uint256 rawTotalSupply = _convertDecimals(NORMALIZED_DECIMALS, decimals[lpTokenId], totalSupply);

        (uint256 amplification,,) = pool.getAmplificationParameter();

        uint256[] memory balances = new uint256[](numAssets);
        balances[indexOf[xToken]] = rawXBalance;
        balances[indexOf[yToken]] = rawYBalance;
        balances[poolQuery.getBptIndex()] = totalSupply;

        uint256[] memory scalingFactors = pool.getScalingFactors();

        _upscaleArray(balances, scalingFactors);

        uint256[] memory updatedBalances = new uint256[](numAssets - 1);
        updatedBalances[0] = balances[indexOf[xToken]];
        updatedBalances[1] = balances[indexOf[yToken]];

        (uint256 rawOutputAmount,) = poolQuery._joinSwapExactTokenInForBptOut(mulDown(rawInputAmount, scalingFactors[isX ? indexOf[xToken] : indexOf[yToken]]), updatedBalances, isX ? 0 : 1, amplification, rawTotalSupply, 0);

        rawOutputAmount = divDown(rawOutputAmount, scalingFactors[poolQuery.getBptIndex()]);

        mintAmount = _convertDecimals(decimals[lpTokenId], NORMALIZED_DECIMALS, rawOutputAmount);
    }

    function withdrawGivenInputAmount(uint256 xBalance, uint256 yBalance, uint256 totalSupply, uint256 burnAmount, SpecifiedToken withdrawnToken) public view returns (uint256 withdrawnAmount) {
        uint256 rawInputAmount = _convertDecimals(NORMALIZED_DECIMALS, decimals[lpTokenId], burnAmount);

        uint256 rawXBalance = _convertDecimals(NORMALIZED_DECIMALS, decimals[xToken], xBalance);
        uint256 rawYBalance = _convertDecimals(NORMALIZED_DECIMALS, decimals[yToken], yBalance);
        uint256 rawTotalSupply = _convertDecimals(NORMALIZED_DECIMALS, decimals[lpTokenId], totalSupply);

        uint256 outputToken = withdrawnToken == SpecifiedToken.X ? xToken : yToken;

        uint256 tokenIndex = indexOf[outputToken] == numAssets - 1 ? indexOf[outputToken] - 1 : indexOf[outputToken];

        (uint256 amplification,,) = pool.getAmplificationParameter();

        uint256[] memory balances = new uint256[](numAssets);
        balances[indexOf[xToken]] = rawXBalance;
        balances[indexOf[yToken]] = rawYBalance;
        balances[poolQuery.getBptIndex()] = totalSupply;

        uint256[] memory scalingFactors = pool.getScalingFactors();

        _upscaleArray(balances, scalingFactors);

        uint256[] memory updatedBalances = new uint256[](numAssets - 1);
        updatedBalances[0] = balances[indexOf[xToken]];
        updatedBalances[1] = balances[indexOf[yToken]];

        (uint256 rawOutputAmount,) = poolQuery._exitSwapExactBptInForTokenOut(mulDown(rawInputAmount, scalingFactors[poolQuery.getBptIndex()]), updatedBalances, tokenIndex, amplification, rawTotalSupply, 0);

        rawOutputAmount = divDown(rawOutputAmount, scalingFactors[indexOf[outputToken]]);

        withdrawnAmount = _convertDecimals(decimals[outputToken], NORMALIZED_DECIMALS, rawOutputAmount);
    }

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

    function _upscaleArray(uint256[] memory amounts, uint256[] memory scalingFactors) internal pure {
        for (uint256 i = 0; i < amounts.length; ++i) {
            amounts[i] = mulDown(amounts[i], scalingFactors[i]);
        }
    }

    function mulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 product = a * b;
        require(a == 0 || product / a == b, "revert");

        return product / 1e18;
    }

    function divDown(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "revert");

        uint256 aInflated = a * 1e18;
        require(a == 0 || aInflated / a == 1e18, "revert"); // mul overflow

        return aInflated / b;
    }

    function mulUp(uint256 a, uint256 b) internal pure returns (uint256 result) {
        uint256 product = a * b;
        uint256 ONE = 1e18;
        require(a == 0 || product / a == b, "revert");

        // The traditional divUp formula is:
        // divUp(x, y) := (x + y - 1) / y
        // To avoid intermediate overflow in the addition, we distribute the division and get:
        // divUp(x, y) := (x - 1) / y + 1
        // Note that this requires x != 0, if x == 0 then the result is zero
        //
        // Equivalent to:
        // result = product == 0 ? 0 : ((product - 1) / FixedPoint.ONE) + 1;
        assembly {
            result := mul(iszero(iszero(product)), add(div(sub(product, 1), ONE), 1))
        }
    }
}
