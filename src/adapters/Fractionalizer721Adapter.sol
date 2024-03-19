// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../interfaces/Interactions.sol";
import "../interfaces/IOcean.sol";
import "../interfaces/IFractionalizer.sol";
import "./OceanAdapter.sol";

contract Fractionalizer721Adapter is OceanAdapter {
    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice Ocean v2 address
    IOcean public immutable shellV2;

    /// @notice ERC721 collection address
    address public immutable nftCollection;

    /// @notice fungible token Ocean ID.
    uint256 public immutable fungibleTokenId;

    /// @notice fungible token Ocean ID in Shell V2.
    uint256 public immutable fungibleTokenIdV2;

    /// @notice fractionalizer exchange rate.
    uint256 public immutable exchangeRate;

    /**
     * @notice only initializing the immutables, mappings & approves tokens
     */
    constructor(address ocean_, address primitive_) OceanAdapter(ocean_, primitive_) {
        shellV2 = IOcean(IFractionalizer(primitive_).ocean());
        shellV2.setApprovalForAll(ocean, true);

        nftCollection = IFractionalizer(primitive_).nftCollection();

        fungibleTokenIdV2 = IFractionalizer(primitive_).fungibleTokenId();

        exchangeRate = IFractionalizer(primitive_).exchangeRate();

        fungibleTokenId = _calculateOceanId(address(shellV2), fungibleTokenIdV2);

        IERC721(nftCollection).setApprovalForAll(ocean, true);
        IERC721(nftCollection).setApprovalForAll(address(shellV2), true);
    }

    /**
     * @dev wraps the underlying token into the Ocean
     */
    function wrapToken(uint256 tokenId, uint256 amount, bytes32 id) internal override {
        Interaction memory interaction = Interaction({ interactionTypeAndAddress: bytes32(0), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(0) });

        if (tokenId == fungibleTokenId) {
            interaction.interactionTypeAndAddress = _fetchInteractionId(address(shellV2), uint256(InteractionType.WrapErc1155));
            interaction.metadata = bytes32(fungibleTokenIdV2);
        } else {
            interaction.interactionTypeAndAddress = _fetchInteractionId(nftCollection, uint256(InteractionType.WrapErc721));
            interaction.metadata = id;
        }

        IOceanInteractions(ocean).doInteraction(interaction);
    }

    /**
     * @dev unwraps the underlying token from the Ocean
     */
    function unwrapToken(uint256 tokenId, uint256 amount, bytes32 id) internal override returns (uint256) {
        Interaction memory interaction = Interaction({ interactionTypeAndAddress: bytes32(0), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(0) });

        if (tokenId == fungibleTokenId) {
            interaction.interactionTypeAndAddress = _fetchInteractionId(address(shellV2), uint256(InteractionType.UnwrapErc1155));
            interaction.metadata = bytes32(fungibleTokenIdV2);
        } else {
            interaction.interactionTypeAndAddress = _fetchInteractionId(nftCollection, uint256(InteractionType.UnwrapErc721));
            interaction.metadata = id;
        }

        IOceanInteractions(ocean).doInteraction(interaction);

        return amount;
    }

    /**
     * @notice
     *   Calculates the output amount for a specified input amount.
     *
     *   @param inputToken Input token id
     *   @param outputToken Output token id
     *   @param inputAmount Input token amount
     *   @param tokenId ERC721 token id
     *
     *   @return outputAmount Output amount
     */
    function primitiveOutputAmount(uint256 inputToken, uint256 outputToken, uint256 inputAmount, bytes32 tokenId) internal override returns (uint256 outputAmount) {
        Interaction[] memory interactions = new Interaction[](2);

        uint256 currentIndex = 0;

        // Interaction to exchange the tokens based on thier v2 ids
        Interaction memory computeInteraction = Interaction({
            interactionTypeAndAddress: _fetchInteractionId(primitive, uint256(InteractionType.ComputeOutputAmount)),
            inputToken: inputToken == fungibleTokenId ? fungibleTokenIdV2 : inputToken,
            outputToken: outputToken == fungibleTokenId ? fungibleTokenIdV2 : outputToken,
            specifiedAmount: inputAmount,
            metadata: tokenId
        });

        // Wrap the underlying input token if it is not Ocean native
        if (inputToken != fungibleTokenId) {
            interactions[currentIndex] = Interaction({ interactionTypeAndAddress: bytes32(0), inputToken: 0, outputToken: 0, specifiedAmount: 1, metadata: tokenId });
            interactions[currentIndex].interactionTypeAndAddress = _fetchInteractionId(nftCollection, uint256(InteractionType.WrapErc721));
            ++currentIndex;
        }

        interactions[currentIndex] = computeInteraction;
        ++currentIndex;

        // Unwrap the underlying output token if it is not Ocean native
        if (outputToken != fungibleTokenId) {
            interactions[currentIndex] = Interaction({ interactionTypeAndAddress: bytes32(0), inputToken: 0, outputToken: 0, specifiedAmount: 1, metadata: tokenId });
            interactions[currentIndex].interactionTypeAndAddress = _fetchInteractionId(nftCollection, uint256(InteractionType.UnwrapErc721));
        }

        // ERC1155 token id's for balance delta
        uint256[] memory ids = new uint256[](2);
        ids[0] = inputToken == fungibleTokenId ? fungibleTokenIdV2 : inputToken;
        ids[1] = outputToken == fungibleTokenId ? fungibleTokenIdV2 : outputToken;

        shellV2.doMultipleInteractions(interactions, ids);

        outputAmount = outputToken == fungibleTokenId ? exchangeRate : 1;
    }

    /**
     * @notice
     *   Get total fungible supply
     *
     *   @param tokenId Fungible token id
     *   @return totalSupply Current total supply.
     */
    function getTokenSupply(uint256 tokenId) external view override returns (uint256 totalSupply) {
        totalSupply = IFractionalizer(primitive).getTokenSupply(tokenId);
    }
}
