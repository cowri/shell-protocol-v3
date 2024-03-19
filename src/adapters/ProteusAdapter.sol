// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../interfaces/IProteus.sol";
import "../interfaces/IOcean.sol";
import "./OceanAdapter.sol";

enum ComputeType {
    Deposit,
    Swap,
    Withdraw
}

contract ProteusAdapter is OceanAdapter {
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

    IOcean public immutable shellV2;

    /// @notice x token Ocean ID.
    uint256 public immutable xToken;

    /// @notice y token Ocean ID.
    uint256 public immutable yToken;

    /// @notice lp token Ocean ID in Shell V2.
    uint256 public immutable lpTokenId;

    /// @notice ETH Ocean ID.
    uint256 public immutable wrappedEtherId;

    mapping(uint256 => uint256) public shellV2Ids;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    /**
     * @notice only initializing the immutables, mappings & approves tokens
     */
    constructor(address ocean_, address primitive_, address xTokenAddress_, address yTokenAddress_) OceanAdapter(ocean_, primitive_) {
        shellV2 = IOcean(IProteus(primitive_).ocean());
        shellV2.setApprovalForAll(ocean, true);

        wrappedEtherId = shellV2.WRAPPED_ETHER_ID();

        uint256 xShellV2 = IProteus(primitive_).xToken();
        uint256 yShellV2 = IProteus(primitive_).yToken();
        uint256 lpShellV2 = IProteus(primitive_).lpTokenId();

        xToken = _calculateOceanId(xTokenAddress_, xTokenAddress_ == address(shellV2) ? xShellV2 : 0);
        yToken = _calculateOceanId(yTokenAddress_, yTokenAddress_ == address(shellV2) ? yShellV2 : 0);
        lpTokenId = _calculateOceanId(address(shellV2), lpShellV2);

        _initializeToken(xToken, xTokenAddress_, xShellV2);
        _initializeToken(yToken, yTokenAddress_, yShellV2);
        _initializeToken(lpTokenId, address(shellV2), lpShellV2);
    }

    /**
     * @dev wraps the underlying token into the Ocean
     * @param tokenId Ocean ID of token to wrap
     * @param amount wrap amount
     */
    function wrapToken(uint256 tokenId, uint256 amount, bytes32 metadata) internal override {
        Interaction memory interaction = Interaction({ interactionTypeAndAddress: bytes32(0), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(0) });

        uint256 etherAmount = 0;

        if (underlying[tokenId] == address(shellV2)) {
            interaction.interactionTypeAndAddress = _fetchInteractionId(address(shellV2), uint256(InteractionType.WrapErc1155));
            interaction.metadata = bytes32(shellV2Ids[tokenId]);
        } else if (tokenId == wrappedEtherId) {
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

        if (underlying[tokenId] == address(shellV2)) {
            interaction.interactionTypeAndAddress = _fetchInteractionId(address(shellV2), uint256(InteractionType.UnwrapErc1155));
            interaction.metadata = bytes32(shellV2Ids[tokenId]);
        } else if (tokenId == wrappedEtherId) {
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
     * @dev swaps/add liquidity/remove liquidity from Shell V2 pool
     * @param inputToken The user is giving this token to the pool
     * @param outputToken The pool is giving this token to the user
     * @param inputAmount The amount of the inputToken the user is giving to the pool
     * @param minimumOutputAmount The minimum amount of tokens expected back after the exchange
     */
    function primitiveOutputAmount(uint256 inputToken, uint256 outputToken, uint256 inputAmount, bytes32 minimumOutputAmount) internal override returns (uint256 outputAmount) {
        ComputeType action = _determineComputeType(inputToken, outputToken);

        uint256 _balanceBefore = _getBalance(outputToken);

        uint256 interactionsCount = 1;

        if (underlying[inputToken] != address(shellV2) && inputToken != wrappedEtherId) ++interactionsCount;
        if (underlying[outputToken] != address(shellV2)) ++interactionsCount;

        Interaction[] memory interactions = new Interaction[](interactionsCount);

        uint256 currentIndex = 0;

        // Interaction to exchange the tokens based on thier v2 ids
        Interaction memory computeInteraction = Interaction({
            interactionTypeAndAddress: _fetchInteractionId(primitive, uint256(InteractionType.ComputeOutputAmount)),
            inputToken: shellV2Ids[inputToken],
            outputToken: shellV2Ids[outputToken],
            specifiedAmount: inputAmount,
            metadata: bytes32(0)
        });

        uint256 etherAmount;

        // Wrap the underlying input token if it is not Ocean native
        if (underlying[inputToken] != address(shellV2)) {
            if (inputToken == wrappedEtherId) {
                etherAmount = inputAmount;
            } else {
                interactions[currentIndex] = Interaction({ interactionTypeAndAddress: bytes32(0), inputToken: 0, outputToken: 0, specifiedAmount: 0, metadata: bytes32(0) });
                interactions[currentIndex].interactionTypeAndAddress = _fetchInteractionId(underlying[inputToken], uint256(InteractionType.WrapErc20));
                interactions[currentIndex].specifiedAmount = inputAmount;
                ++currentIndex;
            }
        }

        interactions[currentIndex] = computeInteraction;
        ++currentIndex;

        // Unwrap the underlying output token if it is not Ocean native
        if (underlying[outputToken] != address(shellV2)) {
            interactions[currentIndex] = Interaction({ interactionTypeAndAddress: bytes32(0), inputToken: 0, outputToken: 0, specifiedAmount: type(uint256).max, metadata: bytes32(0) });

            if (outputToken == wrappedEtherId) {
                interactions[currentIndex].interactionTypeAndAddress = _fetchInteractionId(address(0), uint256(InteractionType.UnwrapEther));
            } else {
                interactions[currentIndex].interactionTypeAndAddress = _fetchInteractionId(underlying[outputToken], uint256(InteractionType.UnwrapErc20));
            }
        }

        // erc1155 token id's for balance delta
        uint256[] memory ids = new uint256[](2);
        ids[0] = shellV2Ids[inputToken];
        ids[1] = shellV2Ids[outputToken];

        shellV2.doMultipleInteractions{ value: etherAmount }(interactions, ids);

        // decimal conversion
        uint256 rawOutputAmount = _getBalance(outputToken) - _balanceBefore;

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
     * @dev Initializes decimals mapping and approves token to be spent by the Ocean and Shell V2
     */
    function _initializeToken(uint256 tokenId, address tokenAddress, uint256 shellV2Id) private {
        underlying[tokenId] = tokenAddress;
        shellV2Ids[tokenId] = shellV2Id;

        if (tokenAddress != address(shellV2) && tokenId != wrappedEtherId) {
            decimals[tokenId] = IERC20Metadata(tokenAddress).decimals();
            IERC20Metadata(tokenAddress).approve(ocean, type(uint256).max);
            IERC20Metadata(tokenAddress).approve(address(shellV2), type(uint256).max);
        } else {
            decimals[tokenId] = 18;
        }
    }

    /**
     * @dev fetches underlying token balances
     */
    function _getBalance(uint256 tokenId) internal view returns (uint256 balance) {
        address tokenAddress = underlying[tokenId];

        if (tokenAddress == address(shellV2)) {
            return shellV2.balanceOf(address(this), shellV2Ids[tokenId]);
        } else if (tokenId == wrappedEtherId) {
            return address(this).balance;
        } else {
            return IERC20Metadata(tokenAddress).balanceOf(address(this));
        }
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

    fallback() external payable { }
}
