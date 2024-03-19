pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../interfaces/Interactions.sol";
import "../../ocean/Ocean.sol";
import "../../fractionalizer/VestingFractionalizer.sol";

contract TestVestingFractionalizer is Test {
    Ocean _ocean;
    ISablierV2LockupLinear _lockUpLinear = ISablierV2LockupLinear(0xFDD9d122B451F549f48c4942c6fa6646D849e8C1);
    IERC20 vestedToken = IERC20(0xe47ba52f326806559c1deC7ddd997F6957d0317D);
    address tokenOwner = 0xF5Fb27b912D987B5b6e02A1B1BE0C1F0740E2c6f;
    address vestingStreamAdmin = 0xfDb06E55Cf044235382511169B6266eECB59101A;
    uint256 tokenId = 7860;
    uint256 streamEndTime = 1769119200;

    VestingFractionalizer _fractionalizer;

    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc");

        _ocean = new Ocean("");
        _fractionalizer = new VestingFractionalizer(IOceanInteractions(address(_ocean)), _lockUpLinear, vestedToken, vestingStreamAdmin, streamEndTime);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function _fetchInteractionId(address token, uint256 interactionType) internal pure returns (bytes32) {
        uint256 packedValue = uint256(uint160(token));
        packedValue |= interactionType << 248;
        return bytes32(abi.encode(packedValue));
    }

    function _calculateOceanId(address tokenContract, uint256 tokenId) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(tokenContract, tokenId)));
    }

    function _getInteraction_and_ids_for_compute_output_amount(bool _order, uint256 fungibleTokenAmount) internal view returns (Interaction[] memory interactions, uint256[] memory ids) {
        ids = new uint256[](2);
        bytes32 interactionIdToComputeOutputAmount = _fetchInteractionId(address(_fractionalizer), uint256(InteractionType.ComputeOutputAmount));
        interactions = new Interaction[](2);
        if (_order) {
            bytes32 interactionIdToWrapErc721 = _fetchInteractionId(address(_lockUpLinear), uint256(InteractionType.WrapErc721));

            // minting fungible tokens
            ids[0] = _calculateOceanId(address(_lockUpLinear), tokenId);
            ids[1] = _fractionalizer.fungibleTokenId();

            // wrap erc721
            interactions[0] = Interaction({ interactionTypeAndAddress: interactionIdToWrapErc721, inputToken: 0, outputToken: 0, specifiedAmount: 1, metadata: bytes32(tokenId) });

            // mint fungible tokens
            interactions[1] = Interaction({ interactionTypeAndAddress: interactionIdToComputeOutputAmount, inputToken: ids[0], outputToken: ids[1], specifiedAmount: 1, metadata: bytes32(tokenId) });
        } else {
            ids[0] = _fractionalizer.fungibleTokenId();
            ids[1] = _calculateOceanId(address(_lockUpLinear), tokenId);

            bytes32 interactionIdToUnWrapErc721 = _fetchInteractionId(address(_lockUpLinear), uint256(InteractionType.UnwrapErc721));

            // burn fungible tokens
            interactions[0] = Interaction({ interactionTypeAndAddress: interactionIdToComputeOutputAmount, inputToken: ids[0], outputToken: ids[1], specifiedAmount: fungibleTokenAmount, metadata: bytes32(tokenId) });

            // unwrap erc721
            interactions[1] = Interaction({ interactionTypeAndAddress: interactionIdToUnWrapErc721, inputToken: 0, outputToken: 0, specifiedAmount: 1, metadata: bytes32(tokenId) });
        }
    } 

    function _getInteraction_and_ids_for_compute_input_amount() internal view returns (Interaction[] memory interactions, uint256[] memory ids) {
        bytes32  interactionIdToComputeInputAmount = _fetchInteractionId(address(_fractionalizer), uint256(InteractionType.ComputeInputAmount));
        ids = new uint256[](2);
        interactions = new Interaction[](2);

            ids[0] = _fractionalizer.fungibleTokenId();
            ids[1] = _calculateOceanId(address(_lockUpLinear), tokenId);

            bytes32 interactionIdToUnWrapErc721 = _fetchInteractionId(address(_lockUpLinear), uint256(InteractionType.UnwrapErc721));

            // burn fungible tokens
            interactions[0] = Interaction({ interactionTypeAndAddress: interactionIdToComputeInputAmount, inputToken: ids[0], outputToken: ids[1], specifiedAmount: 1, metadata: bytes32(tokenId) });

            // unwrap erc721
            interactions[1] = Interaction({ interactionTypeAndAddress: interactionIdToUnWrapErc721, inputToken: 0, outputToken: 0, specifiedAmount: 1, metadata: bytes32(tokenId) });
    }

    function testComputeOutputAmount_reverts_when_invalid_token_ids_are_passed() public {
        vm.startPrank(tokenOwner);
        // approving the Ocean to spend token
        _lockUpLinear.approve(address(_ocean), tokenId);

        (Interaction[] memory interactions, uint256[] memory ids) = _getInteraction_and_ids_for_compute_output_amount(true, 0);
        interactions[1].outputToken = ids[0];

        vm.expectRevert();
        _ocean.doMultipleInteractions(interactions, ids);
    }

    function testComputeInputAmount_reverts_when_called() public {
        vm.startPrank(tokenOwner);

        // approving the Ocean to spend token
        _lockUpLinear.approve(address(_ocean), tokenId);

        (Interaction[] memory interactions, uint256[] memory ids) = _getInteraction_and_ids_for_compute_input_amount();
        interactions[1].inputToken = _fractionalizer.fungibleTokenId();

        vm.expectRevert();
        _ocean.doMultipleInteractions(interactions, ids);
    }

    function testComputeOutputAmount_reverts_when_invalid_amount_passed_and_minting_fungible_tokens() public {
        vm.startPrank(tokenOwner);

        // approving the Ocean to spend token
        _lockUpLinear.approve(address(_ocean), tokenId);

        (Interaction[] memory interactions, uint256[] memory ids) = _getInteraction_and_ids_for_compute_output_amount(true, 0);
        interactions[1].specifiedAmount = 14;

        vm.expectRevert(abi.encodeWithSignature("INVALID_AMOUNT()"));
        _ocean.doMultipleInteractions(interactions, ids);
    }

    function testComputeOutputAmount_reverts_when_unvested_amount_in_stream_is_less_than_swap_amount() public {
        vm.startPrank(tokenOwner);

        // approving the Ocean to spend token
        _lockUpLinear.approve(address(_ocean), tokenId);

        (Interaction[] memory interactions, uint256[] memory ids) = _getInteraction_and_ids_for_compute_output_amount(true, 0);

        uint256 _vestedTokenBalanceBeforeMinting = vestedToken.balanceOf(tokenOwner);

        _ocean.doMultipleInteractions(interactions, ids);

        uint256 _vestedTokenBalanceAfterMinting = vestedToken.balanceOf(tokenOwner);

        (interactions, ids) = _getInteraction_and_ids_for_compute_output_amount(false, _vestedTokenBalanceAfterMinting - _vestedTokenBalanceBeforeMinting);

        vm.expectRevert();
        _ocean.doMultipleInteractions(interactions, ids);
    }

    function testComputeOutputAmount_reverts_when_there_is_no_fungible_supply() public {
        vm.startPrank(tokenOwner);

        // approving the Ocean to spend token
        _lockUpLinear.approve(address(_ocean), tokenId);

        (Interaction[] memory interactions, uint256[] memory ids) = _getInteraction_and_ids_for_compute_output_amount(true, 0);

        _ocean.doMultipleInteractions(interactions, ids);

        vm.warp(block.timestamp + 100 weeks);

        uint256 totalUnderlyingValue = _lockUpLinear.getDepositedAmount(tokenId) - _lockUpLinear.getWithdrawnAmount(tokenId);

        (interactions, ids) = _getInteraction_and_ids_for_compute_output_amount(false, totalUnderlyingValue);

        _ocean.doMultipleInteractions(interactions, ids);

        totalUnderlyingValue = _lockUpLinear.getDepositedAmount(tokenId) - _lockUpLinear.getWithdrawnAmount(tokenId);

        (interactions, ids) = _getInteraction_and_ids_for_compute_output_amount(false, totalUnderlyingValue);

        vm.expectRevert();
        _ocean.doMultipleInteractions(interactions, ids);
    }

    function testComputeOutputAmount_reverts_when_fractionalizing_stream_not_created_by_the_stream_creator() public {
        // token owner of the invalid stream
        tokenOwner = 0x02a52DbC85fFCC15400eF80D8F67Ea5923A7E67b;
        tokenId = 113;
    
        vm.startPrank(tokenOwner);

        // approving the Ocean to spend token
        _lockUpLinear.approve(address(_ocean), tokenId);

        (Interaction[] memory interactions, uint256[] memory ids) = _getInteraction_and_ids_for_compute_output_amount(true, 0);
        interactions[0].metadata = bytes32(tokenId);
        interactions[1].metadata = bytes32(tokenId);

        ids[0] = _calculateOceanId(address(_lockUpLinear), tokenId);

        vm.expectRevert(abi.encodeWithSignature("INVALID_VESTING_STREAM()"));
        _ocean.doMultipleInteractions(interactions, ids);

        vm.stopPrank();
    }

    function testComputeOutputAmount_when_minting_fungible_tokens() public {
        vm.startPrank(tokenOwner);

        // approving the Ocean to spend token
        _lockUpLinear.approve(address(_ocean), tokenId);

        uint256 withdrawableAmount = _lockUpLinear.withdrawableAmountOf(tokenId);

        (Interaction[] memory interactions, uint256[] memory ids) = _getInteraction_and_ids_for_compute_output_amount(true, 0);

        uint256 _vestedTokenBalanceBeforeMinting = vestedToken.balanceOf(tokenOwner);

        (,, uint256[] memory mintIds, uint256[] memory mintAmounts) = _ocean.doMultipleInteractions(interactions, ids);

        uint256 _vestedTokenBalanceAfterMinting = vestedToken.balanceOf(tokenOwner);

        uint256 totalUnderlyingValue = _lockUpLinear.getDepositedAmount(tokenId) - _lockUpLinear.getWithdrawnAmount(tokenId);

        assertEq(_fractionalizer.getTokenSupply(mintIds[0]), totalUnderlyingValue);
        assertEq(mintAmounts.length, 1);
        assertEq(mintAmounts.length, mintIds.length);
        assertEq(mintAmounts[0], totalUnderlyingValue);
        assertEq(_vestedTokenBalanceAfterMinting - _vestedTokenBalanceBeforeMinting, withdrawableAmount);
        vm.stopPrank();
    }

    function testComputeOutputAmount_when_burning_fungible_tokens() public {
        vm.startPrank(tokenOwner);

        // approving the Ocean to spend token
        _lockUpLinear.approve(address(_ocean), tokenId);

        (Interaction[] memory interactions, uint256[] memory ids) = _getInteraction_and_ids_for_compute_output_amount(true, 0);

        uint256 _vestedTokenBalanceBeforeMinting = vestedToken.balanceOf(tokenOwner);

        _ocean.doMultipleInteractions(interactions, ids);

        uint256 _vestedTokenBalanceAfterMinting = vestedToken.balanceOf(tokenOwner);

        // fast forwarding time so there is unvested amount to withdraw
        vm.warp(block.timestamp + 5 weeks);

        uint256 totalUnderlyingValue = _lockUpLinear.getDepositedAmount(tokenId) - _lockUpLinear.getWithdrawnAmount(tokenId);
        vm.startPrank(tokenOwner);

        (interactions, ids) = _getInteraction_and_ids_for_compute_output_amount(false, totalUnderlyingValue);

        uint256 _tokenSupplyBeforeDoInteraction = _fractionalizer.getTokenSupply(_fractionalizer.fungibleTokenId());

        (uint256[] memory burnIds, uint256[] memory burnAmounts,,) = _ocean.doMultipleInteractions(interactions, ids);

        uint256 _tokenSupplyAfterDoInteraction = _fractionalizer.getTokenSupply(_fractionalizer.fungibleTokenId());

        assertEq(_tokenSupplyBeforeDoInteraction - _tokenSupplyAfterDoInteraction, totalUnderlyingValue);
        assertEq(burnIds.length, 1);
        assertEq(burnAmounts.length, burnIds.length);
        assertEq(burnAmounts[0], totalUnderlyingValue);
        assert(_lockUpLinear.ownerOf(tokenId) == tokenOwner);
        vm.stopPrank();
    }

    function testComputeInputAmount_when_burning_fungible_tokens() public {
        vm.startPrank(tokenOwner);

        // approving the Ocean to spend token
        _lockUpLinear.approve(address(_ocean), tokenId);

        (Interaction[] memory interactions, uint256[] memory ids) = _getInteraction_and_ids_for_compute_output_amount(true, 0);

        uint256 _vestedTokenBalanceBeforeMinting = vestedToken.balanceOf(tokenOwner);

        _ocean.doMultipleInteractions(interactions, ids);

        uint256 _vestedTokenBalanceAfterMinting = vestedToken.balanceOf(tokenOwner);

        // fast forwarding time so there is unvested amount to withdraw
        vm.warp(block.timestamp + 5 weeks);

        uint256 totalUnderlyingValue = _lockUpLinear.getDepositedAmount(tokenId) - _lockUpLinear.getWithdrawnAmount(tokenId);
        vm.startPrank(tokenOwner);

        (interactions, ids) = _getInteraction_and_ids_for_compute_input_amount();

        uint256 _tokenSupplyBeforeDoInteraction = _fractionalizer.getTokenSupply(_fractionalizer.fungibleTokenId());

        (uint256[] memory burnIds, uint256[] memory burnAmounts,,) = _ocean.doMultipleInteractions(interactions, ids);

        uint256 _tokenSupplyAfterDoInteraction = _fractionalizer.getTokenSupply(_fractionalizer.fungibleTokenId());

        assertEq(_tokenSupplyBeforeDoInteraction - _tokenSupplyAfterDoInteraction, totalUnderlyingValue);
        assertEq(burnIds.length, 1);
        assertEq(burnAmounts.length, burnIds.length);
        assertEq(burnAmounts[0], totalUnderlyingValue);
        assert(_lockUpLinear.ownerOf(tokenId) == tokenOwner);
        vm.stopPrank();
    }
}
