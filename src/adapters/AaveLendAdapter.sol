// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interfaces/IAave.sol";
import "./OceanAdapter.sol";
import { SpecifiedToken } from "../interfaces/IPoolQuery.sol";

contract AaveLendAdapter is OceanAdapter {
    /// @notice x token Ocean ID.
    uint256 public immutable xToken;

    /// @notice y token Ocean ID.
    uint256 public immutable yToken;

    /// @notice Address of the weth gateway contract
    IWETHGateway public immutable wethGateway;

    /// @notice wrapped token address like wamtic or weth
    IWETH public immutable weth;

    /// @notice atoken address
    IAToken public immutable aToken;

    /// @notice AaveProtocolDataProvider address
    IDataProvider public immutable dataProvider;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    /**
     * @notice only initializing the immutables, mappings & approves tokens
     */
    constructor(address ocean_, address primitive_, address underlyingTokenX_, IWETHGateway _wethGateway, IDataProvider _dataProvider, IWETH _weth) OceanAdapter(ocean_, primitive_) {
        weth = _weth;
        wethGateway = _wethGateway;
        dataProvider = _dataProvider;

        xToken = _calculateOceanId(underlyingTokenX_, 0);
        underlying[xToken] = underlyingTokenX_;
        decimals[xToken] = IERC20Metadata(underlyingTokenX_).decimals();

        (address underlyingTokenY_,,) = _dataProvider.getReserveTokensAddresses(underlyingTokenX_);
        aToken = IAToken(underlyingTokenY_);
        yToken = _calculateOceanId(underlyingTokenY_, 0);
        underlying[yToken] = underlyingTokenY_;
        decimals[yToken] = IERC20Metadata(underlyingTokenY_).decimals();
        _approveToken(underlyingTokenY_);

        if (underlyingTokenX_ == address(weth)) {
            aToken.approve(address(wethGateway), type(uint256).max);
            IERC20Metadata(underlyingTokenX_).approve(ocean, type(uint256).max);
        } else {
            _approveToken(underlyingTokenX_);
        }
    }

    /**
     * @dev wraps the underlying token into the Ocean
     * @param tokenId Ocean ID of token to wrap
     * @param amount wrap amount
     */
    function wrapToken(uint256 tokenId, uint256 amount, bytes32 metadata) internal override {
        address tokenAddress = underlying[tokenId];

        Interaction memory interaction = Interaction({ interactionTypeAndAddress: 0, inputToken: 0, outputToken: 0, specifiedAmount: 0, metadata: bytes32(0) });

        if (tokenAddress == address(0)) {
            IOceanInteractions(ocean).doInteraction{ value: amount }(interaction);
        } else {
            interaction.specifiedAmount = amount;
            interaction.interactionTypeAndAddress = _fetchInteractionId(tokenAddress, uint256(InteractionType.WrapErc20));
            IOceanInteractions(ocean).doInteraction(interaction);
        }
    }

    /**
     * @dev unwraps the underlying token from the Ocean
     * @param tokenId Ocean ID of token to unwrap
     * @param amount unwrap amount
     */
    function unwrapToken(uint256 tokenId, uint256 amount, bytes32 metadata) internal override returns (uint256 unwrappedAmount) {
        address tokenAddress = underlying[tokenId];

        Interaction memory interaction;

        if (tokenAddress == address(0)) {
            interaction = Interaction({ interactionTypeAndAddress: _fetchInteractionId(address(0), uint256(InteractionType.UnwrapEther)), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(0) });
        } else {
            interaction = Interaction({ interactionTypeAndAddress: _fetchInteractionId(tokenAddress, uint256(InteractionType.UnwrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(0) });
        }

        IOceanInteractions(ocean).doInteraction(interaction);

        // handle the unwrap fee scenario
        uint256 unwrapFee = amount / IOceanInteractions(ocean).unwrapFeeDivisor();
        (, uint256 truncated) = _convertDecimals(NORMALIZED_DECIMALS, decimals[tokenId], amount - unwrapFee);
        unwrapFee = unwrapFee + truncated;

        unwrappedAmount = amount - unwrapFee;
    }

    /**
     * @dev deposit/remove liquidity to/from a aave pool
     * @param inputToken The user is giving this token to the pool
     * @param outputToken The pool is giving this token to the user
     * @param inputAmount The amount of the inputToken the user is giving to the pool
     * @param minimumOutputAmount The minimum amount of tokens expected back after the exchange
     */
    function primitiveOutputAmount(uint256 inputToken, uint256 outputToken, uint256 inputAmount, bytes32 minimumOutputAmount) internal override returns (uint256 outputAmount) {
        (uint256 rawInputAmount,) = _convertDecimals(NORMALIZED_DECIMALS, decimals[inputToken], inputAmount);

        // avoid multiple SLOADS
        address underlyingOutputToken = underlying[outputToken];
        address underlyingInputToken = underlying[inputToken];

        if (inputToken == yToken) {
            uint256 balanceBeforeWithdraw;
            uint256 balanceAfterWithdraw;
            uint256 rawOutputAmount;

            if (underlyingOutputToken == address(weth)) {
                balanceBeforeWithdraw = address(this).balance;
                wethGateway.withdrawETH(primitive, type(uint256).max, address(this));
                balanceAfterWithdraw = address(this).balance;
                weth.deposit{ value: balanceAfterWithdraw - balanceBeforeWithdraw }();
            } else {
                balanceBeforeWithdraw = IERC20Metadata(underlyingOutputToken).balanceOf(address(this));
                ILendingPoolV3(primitive).withdraw(underlyingOutputToken, type(uint256).max, address(this));
                balanceAfterWithdraw = IERC20Metadata(underlyingOutputToken).balanceOf(address(this));
            }

            (outputAmount,) = _convertDecimals(decimals[outputToken], NORMALIZED_DECIMALS, balanceAfterWithdraw - balanceBeforeWithdraw);
        } else {
            if (underlyingInputToken == address(weth)) {
                // unwraps WrappedToken back into Native Token
                weth.withdraw(rawInputAmount);

                // deposits native token
                wethGateway.depositETH{ value: rawInputAmount }(primitive, address(this), 0);
            } else {
                ILendingPoolV3(primitive).supply(underlyingInputToken, rawInputAmount, address(this), 0);
            }
            (outputAmount,) = _convertDecimals(decimals[outputToken], NORMALIZED_DECIMALS, rawInputAmount);
        }
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
     * @dev Approves token to be spent by the Ocean and the Curve pool
     */
    function _approveToken(address tokenAddress) private {
        IERC20Metadata(tokenAddress).approve(ocean, type(uint256).max);
        IERC20Metadata(tokenAddress).approve(primitive, type(uint256).max);
    }

    receive() external payable { }
}
