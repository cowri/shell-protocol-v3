// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./OceanAdapter.sol";
import "../interfaces/IBalancerVault.sol";

enum ComputeType {
    Deposit,
    Swap,
    Withdraw
}

/**
 * @notice
 *   balancer adapter to do swaps/deposits and withdrawals through balancer
 */
contract BalancerAdapter is OceanAdapter {
    /////////////////////////////////////////////////////////////////////
    //                             Errors                              //
    /////////////////////////////////////////////////////////////////////
    error INVALID_COMPUTE_TYPE();
    error SLIPPAGE_LIMIT_EXCEEDED();

    /////////////////////////////////////////////////////////////////////
    //                             Events                              //
    /////////////////////////////////////////////////////////////////////
    event Swap(uint256 inputToken, uint256 inputAmount, uint256 outputAmount, bytes32 slippageProtection, address user, bool computeOutput);
    event Deposit(uint256 inputToken, uint256 inputAmount, uint256 outputAmount, bytes32 slippageProtection, address user, bool computeOutput);
    event Withdraw(uint256 outputToken, uint256 inputAmount, uint256 outputAmount, bytes32 slippageProtection, address user, bool computeOutput);

    /// @notice x token Ocean ID.
    uint256 public immutable xToken;

    /// @notice y token Ocean ID.
    uint256 public immutable yToken;

    /// @notice lp token Ocean ID.
    uint256 public immutable lpTokenId;

    /// @notice pool address
    IPool public immutable pool;

    /// @notice pool asset list
    IAsset[] public assets;

    /// @notice map token Ocean IDs to corresponding Curve pool indices
    mapping(uint256 => uint256) public indexOf;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    /**
     * @notice only initializing the immutables, mappings & approves tokens
     */
    constructor(address ocean_, address primitive_, address underlyingTokenX_, address underlyingTokenY_, uint256 tokenXIndex_, uint256 tokenYIndex_, bytes32 poolId_) OceanAdapter(ocean_, primitive_) {
        address xTokenAddress = underlyingTokenX_;
        xToken = _calculateOceanId(xTokenAddress, 0);
        underlying[xToken] = xTokenAddress;
        indexOf[xToken] = tokenXIndex_;
        decimals[xToken] = IERC20Metadata(xTokenAddress).decimals();
        _approveToken(xTokenAddress);

        address yTokenAddress = underlyingTokenY_;
        yToken = _calculateOceanId(yTokenAddress, 0);
        indexOf[yToken] = tokenYIndex_;
        underlying[yToken] = yTokenAddress;
        decimals[yToken] = IERC20Metadata(yTokenAddress).decimals();
        _approveToken(yTokenAddress);

        (address _pool,) = IBalancerVault(primitive).getPool(poolId_);
        pool = IPool(_pool);

        lpTokenId = _calculateOceanId(_pool, 0);
        underlying[lpTokenId] = _pool;
        decimals[lpTokenId] = 18;
        _approveToken(_pool);

        (IERC20[] memory tokens,,) = IBalancerVault(primitive).getPoolTokens(pool.getPoolId());
        for (uint256 i; i < tokens.length;) {
            assets.push(IAsset(address(tokens[i])));
            unchecked {
                ++i;
            }
        }
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

        // avoid multiple SLOADS
        uint256 indexOfInputAmount = indexOf[inputToken];
        uint256 indexOfOutputAmount = indexOf[outputToken];
        uint256 assetLength = assets.length;

        if (action == ComputeType.Swap) {
            IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap({
                poolId: pool.getPoolId(),
                kind: IBalancerVault.SwapKind.GIVEN_IN,
                assetIn: IAsset(underlying[inputToken]),
                assetOut: IAsset(underlying[outputToken]),
                amount: rawInputAmount,
                userData: new bytes(0)
            });

            IBalancerVault.FundManagement memory fundManagement = IBalancerVault.FundManagement({ sender: payable(address(this)), fromInternalBalance: false, recipient: payable(address(this)), toInternalBalance: false });
            rawOutputAmount = IBalancerVault(primitive).swap(singleSwap, fundManagement, uint256(minimumOutputAmount), block.timestamp + 300);
        } else if (action == ComputeType.Deposit) {
            uint256[] memory amounts = new uint256[](assetLength);
            amounts[indexOfInputAmount] = rawInputAmount;

            uint256[] memory amountsWithoutBpt = new uint256[](amounts.length - 1);
            for (uint256 i; i < amountsWithoutBpt.length;) {
                amountsWithoutBpt[i] = amounts[i < pool.getBptIndex() ? i : i + 1];
                unchecked {
                    ++i;
                }
            }

            IBalancerVault.JoinPoolRequest memory joinPool = IBalancerVault.JoinPoolRequest({ assets: assets, maxAmountsIn: amounts, userData: abi.encode(1, amountsWithoutBpt, uint256(minimumOutputAmount)), fromInternalBalance: false });

            uint256 bptBalanceBeforeDeposit = IERC20Metadata(address(pool)).balanceOf(address(this));
            IBalancerVault(primitive).joinPool(pool.getPoolId(), address(this), address(this), joinPool);
            rawOutputAmount = IERC20Metadata(address(pool)).balanceOf(address(this)) - bptBalanceBeforeDeposit;
        } else {
            uint256[] memory amounts = new uint256[](assetLength);
            amounts[indexOfOutputAmount] = uint256(minimumOutputAmount);

            IBalancerVault.ExitPoolRequest memory exitPool = IBalancerVault.ExitPoolRequest({
                assets: assets,
                minAmountsOut: amounts,
                userData: abi.encode(0, rawInputAmount, indexOfOutputAmount < pool.getBptIndex() ? indexOfOutputAmount : indexOfOutputAmount - 1),
                toInternalBalance: false
            });
            address outputTokenAddress = underlying[outputToken];
            uint256 outputTokenBalanceBeforeWithdraw = IERC20Metadata(outputTokenAddress).balanceOf(address(this));

            IBalancerVault(primitive).exitPool(pool.getPoolId(), address(this), payable(address(this)), exitPool);
            rawOutputAmount = IERC20Metadata(outputTokenAddress).balanceOf(address(this)) - outputTokenBalanceBeforeWithdraw;
        }

        (outputAmount,) = _convertDecimals(decimals[outputToken], NORMALIZED_DECIMALS, rawOutputAmount);

        if (uint256(minimumOutputAmount) > outputAmount) revert SLIPPAGE_LIMIT_EXCEEDED();

        if (action == ComputeType.Swap) {
            emit Swap(inputToken, inputAmount, outputAmount, minimumOutputAmount, primitive, true);
        } else if (action == ComputeType.Deposit) {
            emit Deposit(inputToken, inputAmount, outputAmount, minimumOutputAmount, primitive, true);
        } else {
            emit Withdraw(outputToken, inputAmount, outputAmount, minimumOutputAmount, primitive, true);
        }
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
        } else if (((inputToken == xToken) || (inputToken == yToken)) && (outputToken == lpTokenId)) {
            return ComputeType.Deposit;
        } else if ((inputToken == lpTokenId) && ((outputToken == xToken) || (outputToken == yToken))) {
            return ComputeType.Withdraw;
        } else {
            revert INVALID_COMPUTE_TYPE();
        }
    }

    receive() external payable { }
}
