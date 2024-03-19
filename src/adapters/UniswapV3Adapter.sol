// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./OceanAdapter.sol";
import "../interfaces/IUniswapV3Pool.sol";
import "../interfaces/IUniswapv3Callback.sol";

enum ComputeType {
    Swap
}

contract UniswapV3Adapter is OceanAdapter, IUniswapv3Callback {
    /////////////////////////////////////////////////////////////////////
    //                             Errors                              //
    /////////////////////////////////////////////////////////////////////
    error INVALID_COMPUTE_TYPE();
    error SLIPPAGE_LIMIT_EXCEEDED();

    /////////////////////////////////////////////////////////////////////
    //                             Events                              //
    /////////////////////////////////////////////////////////////////////
    event Swap(uint256 inputToken, uint256 inputAmount, uint256 outputAmount, bytes32 slippageProtection, address user, bool computeOutput);

    uint160 internal constant MIN_SQRT_RATIO = 4_295_128_739;

    uint160 internal constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

    /// @notice x token Ocean ID.
    uint256 public immutable xToken;

    /// @notice y token Ocean ID.
    uint256 public immutable yToken;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    /**
     * @notice only initializing the immutables, mappings & approves tokens
     */
    constructor(address ocean_, address primitive_) OceanAdapter(ocean_, primitive_) {
        address xTokenAddress = IUniswapV3Pool(primitive_).token0();
        xToken = _calculateOceanId(xTokenAddress, 0);
        underlying[xToken] = xTokenAddress;
        decimals[xToken] = IERC20Metadata(xTokenAddress).decimals();
        _approveToken(xTokenAddress);

        address yTokenAddress = IUniswapV3Pool(primitive_).token1();
        yToken = _calculateOceanId(yTokenAddress, 0);
        underlying[yToken] = yTokenAddress;
        decimals[yToken] = IERC20Metadata(yTokenAddress).decimals();
        _approveToken(yTokenAddress);
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
        bool isX = inputToken == xToken;

        (uint256 rawInputAmount,) = _convertDecimals(NORMALIZED_DECIMALS, decimals[inputToken], inputAmount);

        _determineComputeType(inputToken, outputToken);

        address underlyingInput = underlying[inputToken];

        // Try swapping.
        (int256 amount0, int256 amount1) = IUniswapV3Pool(primitive).swap({
            recipient: address(this),
            zeroForOne: isX ? true : false,
            amountSpecified: int256(rawInputAmount),
            sqrtPriceLimitX96: isX ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1,
            data: abi.encode(underlyingInput)
        });

        (outputAmount,) = _convertDecimals(decimals[outputToken], NORMALIZED_DECIMALS, isX ? uint256(-amount1) : uint256(-amount0));

        if (uint256(minimumOutputAmount) > outputAmount) revert SLIPPAGE_LIMIT_EXCEEDED();

        emit Swap(inputToken, inputAmount, outputAmount, minimumOutputAmount, primitive, true);
    }

    /// @notice The Uniswap V3 pool callback where the token transfer is expected to happen.
    /// @param _amount0Delta The amount of token 0 being used for the swap.
    /// @param _amount1Delta The amount of token 1 being used for the swap.
    /// @param _data Data passed in by the swap operation.
    function uniswapV3SwapCallback(int256 _amount0Delta, int256 _amount1Delta, bytes calldata _data) external override {
        // Make sure this call is being made from within the swap execution.
        if (msg.sender != primitive) revert();

        // Unpack the data passed in through the swap hook.
        (address _tokenToSwap) = abi.decode(_data, (address));

        // Keep a reference to the amount of tokens that should be sent to fulfill the swap (the positive delta)
        uint256 _amountToSendToPool = _amount0Delta < 0 ? uint256(_amount1Delta) : uint256(_amount0Delta);

        // Transfer the token to the pool.
        bool success = IERC20(_tokenToSwap).transfer(msg.sender, _amountToSendToPool);
        if (!success) revert();
    }

    /**
     * @dev Approves token to be spent by the Ocean and the Curve pool
     */
    function _approveToken(address tokenAddress) private {
        IERC20Metadata(tokenAddress).approve(ocean, type(uint256).max);
        IERC20Metadata(tokenAddress).approve(primitive, type(uint256).max);
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

    receive() external payable { }
}
