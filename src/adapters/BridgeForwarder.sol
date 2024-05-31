// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../interfaces/Interactions.sol";

contract BridgeForwarder {
    event OceanTransaction(address indexed user, address indexed inputToken, address indexed outputToken, bytes32 outputMetadata, uint256 inputAmount, uint256 outputAmount);

    /// @notice normalized decimals to be compatible with the Ocean.
    uint8 constant NORMALIZED_DECIMALS = 18;

    uint256 public constant ethOceanId = 0x97a93559a75ccc959fc63520f07017eed6d512f74e4214a7680ec0eefb5db5b4;

    address public immutable ocean;

    constructor(address _ocean) {
        ocean = _ocean;
    }

    /**
     * @notice Bridge relayer based ocean interaction.
     */
    function doOceanInteraction(address inputToken, address outputToken, bytes32 outputMetadata, address _receiver, bytes32 _minOutputAmount, address[] calldata _primitives, uint256[] calldata _oceanIds) external payable {
        Interaction[] memory interactions;
        uint256 allowanceAmount;
        uint256 startIndex;
        uint256 endIndex;
        uint256 inputAmount;
        if (inputToken == address(0)) {
            interactions = new Interaction[](outputToken == ocean ? _oceanIds.length - 1 : _oceanIds.length);
            endIndex = _oceanIds.length - 1;
            inputAmount = msg.value;
        } else {
            startIndex = 1;
            endIndex = _oceanIds.length;
            interactions = new Interaction[](outputToken == ocean ? _oceanIds.length : _oceanIds.length + 1);
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

        if (outputToken != ocean) {
            interactions[interactions.length - 1] = Interaction({
                interactionTypeAndAddress: outputToken == address(0)
                    ? _fetchInteractionId(address(0), uint256(InteractionType.UnwrapEther))
                    : _fetchInteractionId(outputToken, uint256(outputMetadata != bytes32(0) ? InteractionType.UnwrapErc1155 : InteractionType.UnwrapErc20)),
                inputToken: 0,
                outputToken: 0,
                specifiedAmount: type(uint256).max,
                metadata: outputMetadata
            });

            if (outputMetadata == bytes32(0) && outputToken != address(0)) outputDecimals = IERC20Metadata(outputToken).decimals();
        }

        uint256 balanceBeforeInteraction = outputToken == address(0) ? address(this).balance : outputMetadata != bytes32(0) ? IERC1155(outputToken).balanceOf(address(this), uint256(outputMetadata)) : IERC20Metadata(outputToken).balanceOf(address(this));

        uint256 outputAmount;

        try IOceanInteractions(ocean).doMultipleInteractions{ value: msg.value }(interactions, _oceanIds) returns (uint256[] memory, uint256[] memory, uint256[] memory, uint256[] memory) {
            if (outputToken == address(0)) {
                outputAmount = address(this).balance - balanceBeforeInteraction;
                _handleEthTransfer(_receiver, outputAmount);
            } else if (outputMetadata != bytes32(0)) {
                outputAmount = IERC1155(outputToken).balanceOf(address(this), uint256(outputMetadata)) - balanceBeforeInteraction;
                _handleERC1155Transfer(outputToken, _receiver, outputAmount, uint256(outputMetadata));
            } else {
                outputAmount = IERC20Metadata(outputToken).balanceOf(address(this)) - balanceBeforeInteraction;
                _handleERC20Transfer(outputToken, _receiver, outputAmount);
            }
        } catch {
            // send funds to original owner in case of failure
            if (inputToken == address(0)) {
                outputAmount = msg.value;
                _handleEthTransfer(_receiver, outputAmount);
            } else {
                outputAmount = allowanceAmount;
                _handleERC20Transfer(inputToken, _receiver, outputAmount);
            }
        }

        (uint256 nativeOutputAmount,) = _convertDecimals(outputDecimals, NORMALIZED_DECIMALS, outputAmount);

        emit OceanTransaction(_receiver, inputToken, outputToken, outputMetadata, inputAmount, nativeOutputAmount);
    }

    function _handleEthTransfer(address _receiver, uint256 _amount) internal {
        (bool success,) = _receiver.call{ value: _amount }("");
        if (!success) revert();
    }

    function _handleERC20Transfer(address _token, address _receiver, uint256 _amount) internal {
        bool success = IERC20Metadata(_token).transfer(_receiver, _amount);
        if (!success) revert();
    }

    function _handleERC1155Transfer(address _token, address _receiver, uint256 _amount, uint256 _id) internal {
        IERC1155(_token).safeTransferFrom(address(this), _receiver, _id, _amount, "");
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
