// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

interface IPendleRouter {
    struct ApproxParams {
        uint256 guessMin;
        uint256 guessMax;
        uint256 guessOffchain;
        uint256 maxIteration;
        uint256 eps;
    }

    struct SwapData {
        SwapType swapType;
        address extRouter;
        bytes extCalldata;
        bool needScale;
    }

    enum SwapType {
        NONE,
        KYBERSWAP,
        ONE_INCH,
        // ETH_WETH not used in Aggregator
        ETH_WETH
    }

    struct TokenInput {
        // TOKEN DATA
        address tokenIn;
        uint256 netTokenIn;
        address tokenMintSy;
        // AGGREGATOR DATA
        address pendleSwap;
        SwapData swapData;
    }

    struct TokenOutput {
        // TOKEN DATA
        address tokenOut;
        uint256 minTokenOut;
        address tokenRedeemSy;
        // AGGREGATOR DATA
        address pendleSwap;
        SwapData swapData;
    }

    enum OrderType {
        SY_FOR_PT,
        PT_FOR_SY,
        SY_FOR_YT,
        YT_FOR_SY
    }

    struct Order {
        uint256 salt;
        uint256 expiry;
        uint256 nonce;
        OrderType orderType;
        address token;
        address YT;
        address maker;
        address receiver;
        uint256 makingAmount;
        uint256 lnImpliedRate;
        uint256 failSafeRate;
        bytes permit;
    }

    struct FillOrderParams {
        Order order;
        bytes signature;
        uint256 makingAmount;
    }

    struct LimitOrderData {
        address limitRouter;
        uint256 epsSkipMarket;
        FillOrderParams[] normalFills;
        FillOrderParams[] flashFills;
        bytes optData;
    }

    function swapExactYtForToken(address receiver, address market, uint256 exactYtIn, TokenOutput calldata output, LimitOrderData calldata limit) external returns (uint256 netTokenOut, uint256 netSyFee, uint256 netSyInterm);

    function swapExactTokenForYt(
        address receiver,
        address market,
        uint256 minYtOut,
        ApproxParams calldata guessYtOut,
        TokenInput calldata input,
        LimitOrderData calldata limit
    )
        external
        payable
        returns (uint256 netYtOut, uint256 netSyFee, uint256 netSyInterm);

    function swapExactTokenForPt(
        address receiver,
        address market,
        uint256 minPtOut,
        ApproxParams calldata guessPtOut,
        TokenInput calldata input,
        LimitOrderData calldata limit
    )
        external
        payable
        returns (uint256 netPtOut, uint256 netSyFee, uint256 netSyInterm);

    function swapExactPtForToken(address receiver, address market, uint256 exactPtIn, TokenOutput calldata output, LimitOrderData calldata limit) external returns (uint256 netTokenOut, uint256 netSyFee, uint256 netSyInterm);
}

interface IStandardizedYield { }

interface IPPrincipalToken { }

interface IPYieldToken { }

interface IPendleMarket {
    function readTokens() external view returns (IStandardizedYield _SY, IPPrincipalToken _PT, IPYieldToken _YT);

    function getRewardTokens() external view returns (address[] memory);
}
