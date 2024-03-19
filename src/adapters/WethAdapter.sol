// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interfaces/IProteus.sol";
import "../interfaces/IOcean.sol";
import "./OceanAdapter.sol";
import { SpecifiedToken } from "../interfaces/IPoolQuery.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

enum ComputeType {
    Wrap,
    Unwrap
}

contract WethAdapter is OceanAdapter {
    /////////////////////////////////////////////////////////////////////
    //                             Errors                              //
    /////////////////////////////////////////////////////////////////////
    error INVALID_COMPUTE_TYPE();
    error SLIPPAGE_LIMIT_EXCEEDED();

    /////////////////////////////////////////////////////////////////////
    //                             Events                              //
    /////////////////////////////////////////////////////////////////////
    event Swap(uint256 indexed inputToken, uint256 indexed inputAmount, uint256 indexed outputAmount, bytes32 slippageProtection, address user, bool computeOutput);

    /// @notice ETH Ocean ID
    uint256 public constant xToken = 0x97a93559a75ccc959fc63520f07017eed6d512f74e4214a7680ec0eefb5db5b4;
    uint256 public immutable yToken;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    /**
     * @notice only initializing the immutables, mappings & approves tokens
     */
    constructor(address ocean_, address primitive_) OceanAdapter(ocean_, primitive_) {
        _initializeToken(xToken, address(0));
        yToken = _calculateOceanId(primitive_, 0);
        _initializeToken(yToken, primitive_);
    }

    /**
     * @dev wraps the underlying token into the Ocean
     * @param tokenId Ocean ID of token to wrap
     * @param amount wrap amount
     */
    function wrapToken(uint256 tokenId, uint256 amount, bytes32 metadata) internal override {
        Interaction memory interaction = Interaction({ interactionTypeAndAddress: bytes32(0), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(0) });

        uint256 etherAmount = 0;

        if (tokenId == xToken) {
            interaction.specifiedAmount = 0;
            etherAmount = amount;
        } else {
            interaction.interactionTypeAndAddress = _fetchInteractionId(underlying[tokenId], uint256(InteractionType.WrapErc20));
        }

        IOceanInteractions(ocean).doInteraction{ value: etherAmount }(interaction);
    }

    /**
     * @dev unwraps the underlying token from the Ocean
     * @param tokenId Ocean ID of token to unwrap
     * @param amount unwrap amount
     */
    function unwrapToken(uint256 tokenId, uint256 amount, bytes32 metadata) internal override returns (uint256 unwrappedAmount) {
        Interaction memory interaction = Interaction({ interactionTypeAndAddress: bytes32(0), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(0) });

        if (tokenId == xToken) {
            interaction.interactionTypeAndAddress = _fetchInteractionId(address(0), uint256(InteractionType.UnwrapEther));
        } else {
            interaction.interactionTypeAndAddress = _fetchInteractionId(underlying[tokenId], uint256(InteractionType.UnwrapErc20));
        }

        IOceanInteractions(ocean).doInteraction(interaction);

        // handle the unwrap fee scenario
        uint256 unwrapFee = amount / IOceanInteractions(ocean).unwrapFeeDivisor();
        (, uint256 truncated) = _convertDecimals(NORMALIZED_DECIMALS, decimals[tokenId], amount - unwrapFee);
        unwrapFee = unwrapFee + truncated;

        unwrappedAmount = amount - unwrapFee;
    }

    /**
     * @dev wraps/unwraps ETH to WETH
     * @param inputToken The user is giving this token up
     * @param outputToken The user is getting this token
     * @param inputAmount The amount of the inputToken the user is giving up
     * @param minimumOutputAmount The minimum amount of tokens expected back after the exchange
     */
    function primitiveOutputAmount(uint256 inputToken, uint256 outputToken, uint256 inputAmount, bytes32 minimumOutputAmount) internal override returns (uint256 outputAmount) {
        (uint256 rawInputAmount,) = _convertDecimals(NORMALIZED_DECIMALS, decimals[inputToken], inputAmount);

        ComputeType action = _determineComputeType(inputToken, outputToken);

        uint256 _balanceBefore = _getBalance(outputToken);

        if (action == ComputeType.Wrap) {
            IWETH(primitive).deposit{ value: rawInputAmount }();
        } else {
            IWETH(primitive).withdraw(rawInputAmount);
        }

        uint256 rawOutputAmount = _getBalance(outputToken) - _balanceBefore;

        (outputAmount,) = _convertDecimals(decimals[outputToken], NORMALIZED_DECIMALS, rawOutputAmount);

        if (uint256(minimumOutputAmount) > outputAmount) revert SLIPPAGE_LIMIT_EXCEEDED();

        emit Swap(inputToken, inputAmount, outputAmount, minimumOutputAmount, primitive, true);
    }

    function swapGivenInputAmount(uint256 inputToken, uint256 inputAmount) public view returns (uint256 outputAmount) {
        (uint256 rawInputAmount,) = _convertDecimals(NORMALIZED_DECIMALS, decimals[inputToken], inputAmount);
        (outputAmount,) = _convertDecimals(decimals[inputToken == xToken ? yToken : xToken], NORMALIZED_DECIMALS, rawInputAmount);
    }

    function swapGivenInputAmount(uint256 xBalance, uint256 yBalance, uint256 inputAmount, SpecifiedToken inputToken) public view returns (uint256 outputAmount) {
        bool isX = inputToken == SpecifiedToken.X;
        (uint256 rawInputAmount,) = _convertDecimals(NORMALIZED_DECIMALS, decimals[isX ? xToken : yToken], inputAmount);
        (outputAmount,) = _convertDecimals(decimals[isX ? yToken : xToken], NORMALIZED_DECIMALS, rawInputAmount);
    }

    /**
     * @dev Initializes decimals mapping and approves token to be spent by the Ocean and WETH contract
     */
    function _initializeToken(uint256 tokenId, address tokenAddress) private {
        underlying[tokenId] = tokenAddress;

        if (tokenId != xToken) {
            decimals[tokenId] = IERC20Metadata(tokenAddress).decimals();
            IERC20Metadata(tokenAddress).approve(ocean, type(uint256).max);
            IERC20Metadata(tokenAddress).approve(primitive, type(uint256).max);
        } else {
            decimals[tokenId] = 18;
        }
    }

    /**
     * @dev fetches underlying token balances
     */
    function _getBalance(uint256 tokenId) internal view returns (uint256 balance) {
        address tokenAddress = underlying[tokenId];

        if (tokenId == xToken) {
            return address(this).balance;
        } else {
            return IERC20Metadata(tokenAddress).balanceOf(address(this));
        }
    }

    /**
     * @dev Uses the inputToken and outputToken to determine the ComputeType
     *  (input: ETH, output: WETH) => Wrap
     *  (input: WETH, output: ETH) => Unwrap
     */
    function _determineComputeType(uint256 inputToken, uint256 outputToken) private view returns (ComputeType computeType) {
        if (inputToken == xToken && outputToken == yToken) {
            return ComputeType.Wrap;
        } else if (inputToken == yToken && outputToken == xToken) {
            return ComputeType.Unwrap;
        } else {
            revert INVALID_COMPUTE_TYPE();
        }
    }

    fallback() external payable { }
}
