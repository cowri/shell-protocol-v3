pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../interfaces/Interactions.sol";
import "../../ocean/Ocean.sol";
import "../../adapters/Fractionalizer1155Adapter.sol";

contract TestFractionalizer1155Adapter is Test {
    address primitive = 0x6cefEbACDd6D8eE4ddfD17F0f6A3d1753A4B9f78;
    IERC1155 nftCollection = IERC1155(0x619F1f68a9a3cF939327801012E12f95B0312bB9);
    address tokenOwner = 0x85162b355EEE83eD8d29c3caDA25B80cA86e80d1;
    uint256 tokenId = 4;
    uint256 exchangeRate = 100_000_000_000_000_000_000;
    uint256 _tokenBalance;
    Ocean _ocean;
    Fractionalizer1155Adapter _adapter;

    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc");

        _ocean = new Ocean("");
        _adapter = new Fractionalizer1155Adapter(address(_ocean), primitive);

        _tokenBalance = nftCollection.balanceOf(tokenOwner, tokenId);
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

    function _getFungibleId(uint256 _tokenId) internal view returns (uint256) {
        uint256 nftOceanId = _calculateOceanId(address(nftCollection), uint256(_tokenId));
        uint256 fungibleTokenIdV2 = IFractionalizer(primitive).fungibleTokenIds(nftOceanId);
        if (fungibleTokenIdV2 == 0) fungibleTokenIdV2 = _calculateOceanId(primitive, IFractionalizer(primitive).registeredTokenNonce());
        return _calculateOceanId(address(_adapter.shellV2()), fungibleTokenIdV2);
    }

    function _getInteraction_and_ids_for_compute_output_amount(bool _order, uint256 _amount) internal view returns (Interaction[] memory interactions, uint256[] memory ids) {
        ids = new uint256[](2);
        bytes32 interactionIdToComputeOutputAmount = _fetchInteractionId(address(_adapter), uint256(InteractionType.ComputeOutputAmount));
        interactions = new Interaction[](2);
        if (_order) {
            bytes32 interactionIdToWrapErc1155 = _fetchInteractionId(address(nftCollection), uint256(InteractionType.WrapErc1155));

            // minting fungible tokens
            ids[0] = _calculateOceanId(address(nftCollection), tokenId);
            ids[1] = _getFungibleId(tokenId);

            // wrap erc721
            interactions[0] = Interaction({ interactionTypeAndAddress: interactionIdToWrapErc1155, inputToken: 0, outputToken: 0, specifiedAmount: _amount, metadata: bytes32(tokenId) });

            // mint fungible tokens
            interactions[1] = Interaction({ interactionTypeAndAddress: interactionIdToComputeOutputAmount, inputToken: ids[0], outputToken: ids[1], specifiedAmount: _amount, metadata: bytes32(tokenId) });
        } else {
            ids[0] = _getFungibleId(tokenId);
            ids[1] = _calculateOceanId(address(nftCollection), tokenId);

            bytes32 interactionIdToUnWrapErc1155 = _fetchInteractionId(address(nftCollection), uint256(InteractionType.UnwrapErc1155));

            // burn fungible tokens
            interactions[0] = Interaction({ interactionTypeAndAddress: interactionIdToComputeOutputAmount, inputToken: ids[0], outputToken: ids[1], specifiedAmount: _amount, metadata: bytes32(tokenId) });

            // unwrap erc721
            interactions[1] = Interaction({ interactionTypeAndAddress: interactionIdToUnWrapErc1155, inputToken: 0, outputToken: 0, specifiedAmount: _amount / exchangeRate, metadata: bytes32(tokenId) });
        }
    }

    function testComputeOutputAmount_when_minting_fungible_tokens() public {
        vm.startPrank(tokenOwner);

        // approving the Ocean to spend token
        nftCollection.setApprovalForAll(address(_ocean), true);

        (Interaction[] memory interactions, uint256[] memory ids) = _getInteraction_and_ids_for_compute_output_amount(true, _tokenBalance);

        (,, uint256[] memory mintIds, uint256[] memory mintAmounts) = _ocean.doMultipleInteractions(interactions, ids);
        assertEq(mintAmounts.length, 1);
        assertEq(mintAmounts.length, mintIds.length);
        assertEq(mintAmounts[0], _tokenBalance * exchangeRate);
        assertEq(nftCollection.balanceOf(tokenOwner, tokenId), 0);
        vm.stopPrank();
    }

    function testComputeOutputAmount_when_burning_fungible_tokens() public {
        vm.startPrank(tokenOwner);

        // approving the Ocean to spend token
        nftCollection.setApprovalForAll(address(_ocean), true);

        (Interaction[] memory interactions, uint256[] memory ids) = _getInteraction_and_ids_for_compute_output_amount(true, _tokenBalance);

        _ocean.doMultipleInteractions(interactions, ids);

        assertEq(nftCollection.balanceOf(tokenOwner, tokenId), 0);

        (interactions, ids) = _getInteraction_and_ids_for_compute_output_amount(false, _tokenBalance * exchangeRate);

        (uint256[] memory burnIds, uint256[] memory burnAmounts,,) = _ocean.doMultipleInteractions(interactions, ids);
        assertEq(burnIds.length, 1);
        assertEq(burnAmounts.length, burnIds.length);
        assertEq(burnAmounts[0], _tokenBalance * exchangeRate);
        assertEq(nftCollection.balanceOf(tokenOwner, tokenId), _tokenBalance);
        vm.stopPrank();
    }
}
