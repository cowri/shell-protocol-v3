// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interfaces/IPendle.sol";
import "./OceanAdapter.sol";

enum ComputeType {
    Swap
}

/**
 * @notice
 *   curve2pool adapter contract enabling swapping, adding liquidity & removing liquidity for the curve usdc-usdt pool
 */
contract PendlePTAdapter is OceanAdapter {
    /////////////////////////////////////////////////////////////////////
    //                             Errors                              //
    /////////////////////////////////////////////////////////////////////
    error INVALID_COMPUTE_TYPE();
    error SLIPPAGE_LIMIT_EXCEEDED();

    /////////////////////////////////////////////////////////////////////
    //                             Events                              //
    /////////////////////////////////////////////////////////////////////
    event Swap(uint256 indexed inputToken, uint256 indexed inputAmount, uint256 indexed outputAmount, bytes32 slippageProtection, address user, bool computeOutput);
    event Deposit(uint256 indexed inputToken, uint256 indexed inputAmount, uint256 indexed outputAmount, bytes32 slippageProtection, address user, bool computeOutput);
    event Withdraw(uint256 indexed outputToken, uint256 indexed inputAmount, uint256 indexed outputAmount, bytes32 slippageProtection, address user, bool computeOutput);

    uint256 constant MAX_APPROVAL_AMOUNT = type(uint256).max;

    /// @notice x token Ocean ID.
    uint256 public immutable xToken;

    /// @notice y token Ocean ID.
    uint256 public immutable yToken;

    IPendleRouter public immutable router;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    /**
     * @notice only initializing the immutables, mappings & approves tokens
     */
    constructor(address ocean_, address primitive_, address baseToken_, IPendleRouter router_) OceanAdapter(ocean_, primitive_) {
        router = router_;

        xToken = _calculateOceanId(baseToken_, 0);
        underlying[xToken] = baseToken_;
        decimals[xToken] = IERC20Metadata(baseToken_).decimals();
        _approveToken(baseToken_);

        (, IPPrincipalToken _PT,) = IPendleMarket(primitive_).readTokens();
        yToken = _calculateOceanId(address(_PT), 0);
        underlying[yToken] = address(_PT);
        decimals[yToken] = IERC20Metadata(address(_PT)).decimals();
        _approveToken(address(_PT));
    }

    /**
     * @dev wraps the underlying token into the Ocean
     * @param tokenId Ocean ID of token to wrap
     * @param amount wrap amount
     */
    function wrapToken(uint256 tokenId, uint256 amount, bytes32 metadata) internal override {
        address tokenAddress = underlying[tokenId];

        Interaction memory interaction = Interaction({ interactionTypeAndAddress: _fetchInteractionId(tokenAddress, uint256(InteractionType.WrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(0) });

        IOceanInteractions(ocean).doInteraction(interaction);
    }

    /**
     * @dev unwraps the underlying token from the Ocean
     * @param tokenId Ocean ID of token to unwrap
     * @param amount unwrap amount
     */
    function unwrapToken(uint256 tokenId, uint256 amount, bytes32 metadata) internal override returns (uint256 unwrappedAmount) {
        address tokenAddress = underlying[tokenId];

        Interaction memory interaction = Interaction({ interactionTypeAndAddress: _fetchInteractionId(tokenAddress, uint256(InteractionType.UnwrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(0) });

        IOceanInteractions(ocean).doInteraction(interaction);

        // handle the unwrap fee scenario
        uint256 unwrapFee = amount / IOceanInteractions(ocean).unwrapFeeDivisor();
        (, uint256 truncated) = _convertDecimals(NORMALIZED_DECIMALS, decimals[tokenId], amount - unwrapFee);
        unwrapFee = unwrapFee + truncated;

        unwrappedAmount = amount - unwrapFee;
    }

    /**
     * @dev swaps/add liquidity/remove liquidity from Curve 2pool
     * @param inputToken The user is giving this token to the pool
     * @param outputToken The pool is giving this token to the user
     * @param inputAmount The amount of the inputToken the user is giving to the pool
     * @param minimumOutputAmount The minimum amount of tokens expected back after the exchange
     */
    function primitiveOutputAmount(uint256 inputToken, uint256 outputToken, uint256 inputAmount, bytes32 minimumOutputAmount) internal override returns (uint256 outputAmount) {
        (uint256 rawInputAmount,) = _convertDecimals(NORMALIZED_DECIMALS, decimals[inputToken], inputAmount);

        ComputeType action = _determineComputeType(inputToken, outputToken);

        uint256 rawOutputAmount;

        address underlyingInput = underlying[inputToken];
        address underlyingOutput = underlying[outputToken];

        if (inputToken == xToken) {
            IPendleRouter.TokenInput memory tokenInput;
            tokenInput.tokenIn = underlyingInput;
            tokenInput.netTokenIn = rawInputAmount;
            tokenInput.tokenMintSy = underlyingInput;

            IPendleRouter.ApproxParams memory approxParams;
            approxParams.guessMax = type(uint256).max;
            approxParams.maxIteration = 256;
            approxParams.eps = 1e14;

            IPendleRouter.LimitOrderData memory limitOrderData;

            (rawOutputAmount,,) = router.swapExactTokenForPt(address(this), primitive, 0, approxParams, tokenInput, limitOrderData);
        } else {
            IPendleRouter.TokenOutput memory tokenOutput;
            tokenOutput.tokenOut = underlyingOutput;
            tokenOutput.minTokenOut = 0;
            tokenOutput.tokenRedeemSy = underlyingOutput;

            IPendleRouter.LimitOrderData memory limitOrderData;

            (rawOutputAmount,,) = router.swapExactPtForToken(address(this), primitive, rawInputAmount, tokenOutput, limitOrderData);
        }

        (outputAmount,) = _convertDecimals(decimals[outputToken], NORMALIZED_DECIMALS, rawOutputAmount);

        if (uint256(minimumOutputAmount) > outputAmount) revert SLIPPAGE_LIMIT_EXCEEDED();

        emit Swap(inputToken, inputAmount, outputAmount, minimumOutputAmount, primitive, true);
    }

    /**
     * @dev Approves token to be spent by the Ocean and the Curve pool
     */
    function _approveToken(address tokenAddress) private {
        IERC20Metadata(tokenAddress).approve(ocean, MAX_APPROVAL_AMOUNT);
        IERC20Metadata(tokenAddress).approve(address(router), MAX_APPROVAL_AMOUNT);
    }

    /**
     * @dev Uses the inputToken and outputToken to determine the ComputeType
     *  (input: xToken, output: yToken) | (input: yToken, output: xToken) => SWAP
     *  base := xToken | yToken
     *  (input: base, output: lpToken) => DEPOSIT
     *  (input: lpToken, output: base) => WITHDRAW
     */
    function _determineComputeType(uint256 inputToken, uint256 outputToken) private view returns (ComputeType computeType) {
        if (((inputToken == xToken) && (outputToken == yToken)) || ((inputToken == yToken) && (outputToken == xToken))) {
            return ComputeType.Swap;
        } else {
            revert INVALID_COMPUTE_TYPE();
        }
    }
}
