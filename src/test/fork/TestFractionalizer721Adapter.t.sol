pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../interfaces/Interactions.sol";
import "../../ocean/Ocean.sol";
import "../../adapters/Fractionalizer721Adapter.sol";
import "../../interfaces/IFractionalizer.sol";

contract TestFractionalizer721Adapter is Test {
    address primitive = 0x2946012D62f7b9B5E6AEBfE364b91CBe5f32B6A4;
    IERC721 nftCollection = IERC721(0x642FfAb2752Df3BCE97083709F36080fb1482c80);
    address tokenOwner = 0xCB9055fc2a8f0F27041dC238574100a22dF0C15e;
    uint256 tokenId = 14_750;
    uint256 exchangeRate = 100_000_000_000_000_000_000;
    Ocean _ocean;
    Fractionalizer721Adapter _adapter;

    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc");

        _ocean = new Ocean("");
        _adapter = new Fractionalizer721Adapter(address(_ocean), primitive);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function _fetchInteractionId(address token, uint256 interactionType) internal pure returns (bytes32) {
        uint256 packedValue = uint256(uint160(token));
        packedValue |= interactionType << 248;
        return bytes32(abi.encode(packedValue));
    }

    function _calculateOceanId(address tokenContract, uint256 tokenId) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(tokenContract, tokenId)));
    }

    function _getInteraction_and_ids_for_compute_output_amount(bool _order) internal view returns (Interaction[] memory interactions, uint256[] memory ids) {
        ids = new uint256[](2);
        bytes32 interactionIdToComputeOutputAmount = _fetchInteractionId(address(_adapter), uint256(InteractionType.ComputeOutputAmount));
        interactions = new Interaction[](2);
        if (_order) {
            bytes32 interactionIdToWrapErc721 = _fetchInteractionId(address(nftCollection), uint256(InteractionType.WrapErc721));

            // minting fungible tokens
            ids[0] = _calculateOceanId(address(nftCollection), tokenId);
            ids[1] = _adapter.fungibleTokenId();

            // wrap erc721
            interactions[0] = Interaction({ interactionTypeAndAddress: interactionIdToWrapErc721, inputToken: 0, outputToken: 0, specifiedAmount: 1, metadata: bytes32(tokenId) });

            // mint fungible tokens
            interactions[1] = Interaction({ interactionTypeAndAddress: interactionIdToComputeOutputAmount, inputToken: ids[0], outputToken: ids[1], specifiedAmount: 1, metadata: bytes32(tokenId) });
        } else {
            ids[0] = _adapter.fungibleTokenId();
            ids[1] = _calculateOceanId(address(nftCollection), tokenId);

            bytes32 interactionIdToUnWrapErc721 = _fetchInteractionId(address(nftCollection), uint256(InteractionType.UnwrapErc721));

            // burn fungible tokens
            interactions[0] = Interaction({ interactionTypeAndAddress: interactionIdToComputeOutputAmount, inputToken: ids[0], outputToken: ids[1], specifiedAmount: exchangeRate, metadata: bytes32(tokenId) });

            // unwrap erc721
            interactions[1] = Interaction({ interactionTypeAndAddress: interactionIdToUnWrapErc721, inputToken: 0, outputToken: 0, specifiedAmount: 1, metadata: bytes32(tokenId) });
        }
    }

    function testComputeOutputAmount_when_minting_fungible_tokens() public {
        vm.startPrank(tokenOwner);

        // approving the Ocean to spend token
        nftCollection.approve(address(_ocean), tokenId);

        (Interaction[] memory interactions, uint256[] memory ids) = _getInteraction_and_ids_for_compute_output_amount(true);

        (,, uint256[] memory mintIds, uint256[] memory mintAmounts) = _ocean.doMultipleInteractions(interactions, ids);
        assertEq(mintAmounts.length, 1);
        assertEq(mintAmounts.length, mintIds.length);
        assertEq(mintAmounts[0], exchangeRate);
        assert(nftCollection.ownerOf(tokenId) == IFractionalizer(primitive).ocean());
        vm.stopPrank();
    }

    function testComputeOutputAmount_when_burning_fungible_tokens() public {
        vm.startPrank(tokenOwner);

        // approving the Ocean to spend token
        nftCollection.approve(address(_ocean), tokenId);

        (Interaction[] memory interactions, uint256[] memory ids) = _getInteraction_and_ids_for_compute_output_amount(true);

        _ocean.doMultipleInteractions(interactions, ids);

        (interactions, ids) = _getInteraction_and_ids_for_compute_output_amount(false);

        (uint256[] memory burnIds, uint256[] memory burnAmounts,,) = _ocean.doMultipleInteractions(interactions, ids);
        assertEq(burnIds.length, 1);
        assertEq(burnAmounts.length, burnIds.length);
        assertEq(burnAmounts[0], exchangeRate);
        assert(nftCollection.ownerOf(tokenId) == tokenOwner);
        vm.stopPrank();
    }
}
