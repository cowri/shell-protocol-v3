// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interfaces/Interactions.sol";

contract BridgeInitiator {
    event TokensBridged(address indexed inputToken, address indexed outputToken, uint256 outputAmount);

    /// @notice normalized decimals to be compatible with the Ocean.
    uint8 constant NORMALIZED_DECIMALS = 18;

    uint256 public constant ethOceanId = 0x97a93559a75ccc959fc63520f07017eed6d512f74e4214a7680ec0eefb5db5b4;

    address public immutable ocean;

    address public immutable dlnSource;

    uint256 public immutable fee;

    constructor(address _ocean, address _dlnSource, uint256 _fee) {
        ocean = _ocean;
        dlnSource = _dlnSource;
        fee = _fee;
    }

    /**
     * @notice Bridge relayer based ocean interaction.
     */
    function doOceanInteraction(address inputToken, address outputToken, bytes32 outputMetadata, bytes32 _minOutputAmount, address[] calldata _primitives, uint256[] calldata _oceanIds, bytes calldata _bridgeData) external payable {
        Interaction[] memory interactions;
        uint256 allowanceAmount;
        uint256 startIndex;
        uint256 endIndex;
        uint256 inputAmount;

        if (outputMetadata != bytes32(0) || outputToken == ocean) revert();

        if (inputToken == address(0)) {
            interactions = new Interaction[](_oceanIds.length);
            endIndex = _oceanIds.length - 1;
            inputAmount = msg.value;
        } else {
            startIndex = 1;
            endIndex = _oceanIds.length;
            interactions = new Interaction[](_oceanIds.length + 1);
            allowanceAmount = IERC20Metadata(inputToken).allowance(msg.sender, address(this));

            IERC20Metadata(inputToken).transferFrom(msg.sender, address(this), allowanceAmount);

            uint8 decimals = IERC20Metadata(inputToken).decimals();

            IERC20Metadata(inputToken).approve(ocean, allowanceAmount);

            (uint256 convertedAmount,) = _convertDecimals(decimals, NORMALIZED_DECIMALS, allowanceAmount);

            interactions[0] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(inputToken, uint256(InteractionType.WrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: convertedAmount, metadata: 0 });

            inputAmount = convertedAmount;
        }

        for (uint256 i = startIndex; i < endIndex;) {
            interactions[i] = Interaction({
                interactionTypeAndAddress: _fetchInteractionId(address(_primitives[startIndex == 1 ? i - 1 : i]), uint256(InteractionType.ComputeOutputAmount)),
                inputToken: _oceanIds[startIndex == 1 ? i - 1 : i],
                outputToken: _oceanIds[startIndex == 1 ? i : i + 1],
                specifiedAmount: type(uint256).max,
                metadata: i == endIndex - 1 ? _minOutputAmount : bytes32(0)
            });
            unchecked {
                ++i;
            }
        }

        uint8 outputDecimals = 18;

        interactions[interactions.length - 1] = Interaction({
            interactionTypeAndAddress: outputToken == address(0) ? _fetchInteractionId(address(0), uint256(InteractionType.UnwrapEther)) : _fetchInteractionId(outputToken, uint256(InteractionType.UnwrapErc20)),
            inputToken: 0,
            outputToken: 0,
            specifiedAmount: type(uint256).max,
            metadata: outputMetadata
        });

        if (outputToken != address(0)) outputDecimals = IERC20Metadata(outputToken).decimals();

        uint256 balanceBeforeInteraction = outputToken == address(0) ? address(this).balance : IERC20Metadata(outputToken).balanceOf(address(this));

        uint256 outputAmount;

        IOceanInteractions(ocean).doMultipleInteractions{ value: msg.value - fee }(interactions, _oceanIds);
        if (outputToken == address(0)) {
            outputAmount = address(this).balance - balanceBeforeInteraction;
            _handleBridge(outputToken, outputAmount, _bridgeData);
        } else {
            outputAmount = IERC20Metadata(outputToken).balanceOf(address(this)) - balanceBeforeInteraction;
            _handleBridge(outputToken, outputAmount, _bridgeData);
        }

        emit TokensBridged(inputToken, outputToken, outputAmount);
    }

    function _handleBridge(address _token, uint256 _amount, bytes calldata _bridgeData) internal {
        if (_token != address(0)) IERC20Metadata(_token).approve(dlnSource, _amount);

        (bool success,) = dlnSource.call{ value: _token == address(0) ? _amount : fee }(_bridgeData);
        if (!success) revert();
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
     * @return truncatedAmount if (from > to), there may be some truncation, it
     *  is up to the caller to decide what to do with the truncated amount.
     */
    function _convertDecimals(uint8 decimalsFrom, uint8 decimalsTo, uint256 amountToConvert) internal pure returns (uint256 convertedAmount, uint256 truncatedAmount) {
        if (decimalsFrom == decimalsTo) {
            // no shift
            convertedAmount = amountToConvert;
            truncatedAmount = 0;
        } else if (decimalsFrom < decimalsTo) {
            // Decimal shift left (add precision)
            uint256 shift = 10 ** (uint256(decimalsTo - decimalsFrom));
            convertedAmount = amountToConvert * shift;
            truncatedAmount = 0;
        } else {
            // Decimal shift right (remove precision) -> truncation
            uint256 shift = 10 ** (uint256(decimalsFrom - decimalsTo));
            convertedAmount = amountToConvert / shift;
            truncatedAmount = amountToConvert % shift;
        }
    }

    /**
     * @notice used to fetch the Ocean interaction ID
     */
    function _fetchInteractionId(address token, uint256 interactionType) internal pure returns (bytes32) {
        uint256 packedValue = uint256(uint160(token));
        packedValue |= interactionType << 248;
        return bytes32(abi.encode(packedValue));
    }

    /**
     * @notice calculates Ocean ID for a underlying token
     */
    function _calculateOceanId(address tokenAddress, uint256 tokenId) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(tokenAddress, tokenId)));
    }

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    receive() external payable { }
}