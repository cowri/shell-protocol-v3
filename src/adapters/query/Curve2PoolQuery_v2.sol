// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

import { IPoolQuery, SpecifiedToken } from "../../interfaces/IPoolQuery.sol";
import "../Curve2PoolAdapter.sol";

contract Curve2PoolQuery_v2 is IPoolQuery {
    ICurveQuery public immutable pool;
    ICurveQuery public immutable statelessPool;

    uint256 public immutable xToken;
    uint256 public immutable yToken;
    uint256 public immutable lpTokenId;

    mapping(uint256 => uint8) public decimals;

    uint8 public constant NORMALIZED_DECIMALS = 18;

    constructor(address adapter_, address poolLogic_) {
        Curve2PoolAdapter adapter = Curve2PoolAdapter(adapter_);
        pool = ICurveQuery(adapter.primitive());
        statelessPool = ICurveQuery(poolLogic_);

        xToken = adapter.xToken();
        yToken = adapter.yToken();
        lpTokenId = adapter.lpTokenId();

        decimals[xToken] = adapter.decimals(xToken);
        decimals[yToken] = adapter.decimals(yToken);
        decimals[lpTokenId] = adapter.decimals(lpTokenId);
    }

    function swapGivenInputAmount(uint256 inputToken, uint256 inputAmount) public view returns (uint256 outputAmount) {
        uint256 rawInputAmount = _convertDecimals(NORMALIZED_DECIMALS, decimals[inputToken], inputAmount);

        bool isX = inputToken == xToken;

        int128 inputID = isX ? int128(0) : int128(1);
        int128 outputID = isX ? int128(1) : int128(0);

        uint256 rawOutputAmount = pool.get_dy(inputID, outputID, rawInputAmount);

        uint256 outputToken = isX ? yToken : xToken;

        outputAmount = _convertDecimals(decimals[outputToken], NORMALIZED_DECIMALS, rawOutputAmount);
    }

    function swapGivenInputAmount(uint256 xBalance, uint256 yBalance, uint256 inputAmount, SpecifiedToken inputToken) public view returns (uint256 outputAmount) {
        bool isX = inputToken == SpecifiedToken.X;

        uint256 rawInputAmount = _convertDecimals(NORMALIZED_DECIMALS, decimals[isX ? xToken : yToken], inputAmount);

        uint256 rawXBalance = _convertDecimals(NORMALIZED_DECIMALS, decimals[xToken], xBalance);
        uint256 rawYBalance = _convertDecimals(NORMALIZED_DECIMALS, decimals[yToken], yBalance);

        int128 inputID = isX ? int128(0) : int128(1);
        int128 outputID = isX ? int128(1) : int128(0);

        uint256[] memory balances = new uint256[](2);
        balances[0] = rawXBalance;
        balances[1] = rawYBalance;

        uint256 rawOutputAmount = statelessPool.get_dy(balances, inputID, outputID, rawInputAmount, address(pool));

        uint256 outputToken = isX ? yToken : xToken;

        outputAmount = _convertDecimals(decimals[outputToken], NORMALIZED_DECIMALS, rawOutputAmount);
    }

    function depositGivenInputAmount(uint256 depositToken, uint256 depositAmount) public view returns (uint256 mintAmount) {
        uint256 rawInputAmount = _convertDecimals(NORMALIZED_DECIMALS, decimals[depositToken], depositAmount);

        uint256[] memory inputAmounts = new uint256[](2);

        inputAmounts[depositToken == xToken ? 0 : 1] = rawInputAmount;

        uint256 rawOutputAmount = pool.calc_token_amount(inputAmounts, true);

        mintAmount = _convertDecimals(decimals[lpTokenId], NORMALIZED_DECIMALS, rawOutputAmount);
    }

    function depositGivenInputAmount(uint256 xBalance, uint256 yBalance, uint256 totalSupply, uint256 depositAmount, SpecifiedToken depositToken) public view returns (uint256 mintAmount) {
        bool isX = depositToken == SpecifiedToken.X;

        uint256 rawInputAmount = _convertDecimals(NORMALIZED_DECIMALS, decimals[isX ? xToken : yToken], depositAmount);

        uint256 rawXBalance = _convertDecimals(NORMALIZED_DECIMALS, decimals[xToken], xBalance);
        uint256 rawYBalance = _convertDecimals(NORMALIZED_DECIMALS, decimals[yToken], yBalance);
        uint256 rawTotalSupply = _convertDecimals(NORMALIZED_DECIMALS, decimals[lpTokenId], totalSupply);

        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[isX ? 0 : 1] = rawInputAmount;

        uint256[] memory balances = new uint256[](2);
        balances[0] = rawXBalance;
        balances[1] = rawYBalance;

        uint256 rawOutputAmount = statelessPool.calc_token_amount(balances, rawTotalSupply, inputAmounts, true, address(pool));

        mintAmount = _convertDecimals(decimals[lpTokenId], NORMALIZED_DECIMALS, rawOutputAmount);
    }

    function withdrawGivenInputAmount(uint256 withdrawnToken, uint256 burnAmount) public view returns (uint256 withdrawnAmount) {
        uint256 rawInputAmount = _convertDecimals(NORMALIZED_DECIMALS, decimals[lpTokenId], burnAmount);

        int128 outputID = withdrawnToken == xToken ? int128(0) : int128(1);

        uint256 rawOutputAmount = pool.calc_withdraw_one_coin(rawInputAmount, outputID);

        withdrawnAmount = _convertDecimals(decimals[withdrawnToken], NORMALIZED_DECIMALS, rawOutputAmount);
    }

    function withdrawGivenInputAmount(uint256 xBalance, uint256 yBalance, uint256 totalSupply, uint256 burnAmount, SpecifiedToken withdrawnToken) public view returns (uint256 withdrawnAmount) {
        uint256 rawInputAmount = _convertDecimals(NORMALIZED_DECIMALS, decimals[lpTokenId], burnAmount);

        uint256 rawXBalance = _convertDecimals(NORMALIZED_DECIMALS, decimals[xToken], xBalance);
        uint256 rawYBalance = _convertDecimals(NORMALIZED_DECIMALS, decimals[yToken], yBalance);
        uint256 rawTotalSupply = _convertDecimals(NORMALIZED_DECIMALS, decimals[lpTokenId], totalSupply);

        int128 outputID = withdrawnToken == SpecifiedToken.X ? int128(0) : int128(1);

        uint256[] memory balances = new uint256[](2);
        balances[0] = rawXBalance;
        balances[1] = rawYBalance;

        uint256 rawOutputAmount = statelessPool.calc_withdraw_one_coin(balances, rawTotalSupply, rawInputAmount, outputID, address(pool));

        withdrawnAmount = _convertDecimals(decimals[outputID == 0 ? xToken : yToken], NORMALIZED_DECIMALS, rawOutputAmount);
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
}

interface ICurveQuery {
    function totalSupply() external view returns (uint256);

    function get_balances() external view returns (uint256[] memory);

    function coins(uint256 i) external view returns (address);

    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);

    function get_dy(uint256[] memory balances, int128 i, int128 j, uint256 dx, address pool) external view returns (uint256);

    function calc_token_amount(uint256[] memory _amounts, bool _is_deposit) external view returns (uint256);

    function calc_token_amount(uint256[] memory balances, uint256 totalSupply, uint256[] memory _amounts, bool _is_deposit, address pool) external view returns (uint256);

    function calc_withdraw_one_coin(uint256 _burn_amount, int128 i) external view returns (uint256);

    function calc_withdraw_one_coin(uint256[] memory balances, uint256 totalSupply, uint256 _burn_amount, int128 i, address pool) external view returns (uint256);
}
