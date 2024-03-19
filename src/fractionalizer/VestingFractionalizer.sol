// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOceanPrimitive } from "../interfaces/IOceanPrimitive.sol";
import { IOceanToken } from "../interfaces/IOceanToken.sol";
import "../interfaces/Interactions.sol";
import "../interfaces/ISablierV2LockupLinear.sol";

/**
 * @notice
 *   Allows vesting token owners to fractionalize their tokens
 *
 *   @dev
 *   Inherits from -
 *   IOceanPrimitive: This is an Ocean primitive and hence the methods can only be accessed by the Ocean contract.
 */
contract VestingFractionalizer is IOceanPrimitive {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//
    error UNAUTHORIZED();
    error INVALID_AMOUNT();
    error INVALID_TOKEN_ID();
    error INVALID_VESTING_STREAM();

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//
    /**
     * @notice
     *  ocean contract address.
     */
    IOceanInteractions public immutable ocean;

    /**
     * @notice
     * sablier lock linear stream contract.
     */
    ISablierV2LockupLinear public immutable lockupLinear;

    /**
     * @notice
     * shell token address.
     */
    IERC20 public immutable shell;

    /**
     * @notice
     * stream creator address.
     */
    address public immutable streamCreator;

    /**
     * @notice
     *  fungible token id
     */
    uint256 public immutable fungibleTokenId;

    /**
     * @notice
     *  end time for filtering valid vesting streams
     */
    uint256 public immutable streamEndTime;

    /**
     * @notice
     *  fungible token total supply
     */
    uint256 public fungibleTokenSupply;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//
    constructor(IOceanInteractions ocean_, ISablierV2LockupLinear lockupLinear_, IERC20 shell_, address _streamCreator, uint256 _streamEndTime) {
        ocean = ocean_;
        lockupLinear = lockupLinear_;
        shell = shell_;
        streamCreator = _streamCreator;
        streamEndTime = _streamEndTime;

        uint256[] memory registeredToken = IOceanToken(address(ocean_)).registerNewTokens(0, 1);
        fungibleTokenId = registeredToken[0];

        lockupLinear.setApprovalForAll(address(ocean_), true);
    }

    /**
     * @notice Modifier to make sure msg.sender is the Ocean contract.
     */
    modifier onlyOcean() {
        if (msg.sender != address(ocean)) revert UNAUTHORIZED();
        _;
    }

    function _withdrawMax(uint256 _id, address _user) internal {
        lockupLinear.withdrawMax(_id, _user);
    }

    /**
     * @dev wraps the underlying token into the Ocean
     */
    function wrapERC721(uint256 _tokenId) internal {
        Interaction memory interaction =
            Interaction({ interactionTypeAndAddress: _fetchInteractionId(address(lockupLinear), uint256(InteractionType.WrapErc721)), inputToken: 0, outputToken: 0, specifiedAmount: 1, metadata: bytes32(_tokenId) });

        ocean.doInteraction(interaction);
    }

    /**
     * @dev unwraps the underlying token from the Ocean
     */
    function unwrapERC721(uint256 _tokenId) internal {
        Interaction memory interaction =
            Interaction({ interactionTypeAndAddress: _fetchInteractionId(address(lockupLinear), uint256(InteractionType.UnwrapErc721)), inputToken: 0, outputToken: 0, specifiedAmount: 1, metadata: bytes32(_tokenId) });

        ocean.doInteraction(interaction);
    }

    /**
     * @notice
     *   Calculates the output amount for a specified input amount.
     *
     *   @param inputToken Input token id
     *   @param outputToken Output token id
     *   @param inputAmount Input token amount
     *   @param tokenId erc721 token id
     *
     *   @return outputAmount Output amount
     */
    function computeOutputAmount(uint256 inputToken, uint256 outputToken, uint256 inputAmount, address user, bytes32 tokenId) external override onlyOcean returns (uint256 outputAmount) {
        uint256 nftOceanId = _calculateOceanId(address(lockupLinear), uint256(tokenId));

        if (inputToken == nftOceanId && outputToken == fungibleTokenId) {
            if (inputAmount != 1) revert INVALID_AMOUNT();

            // valid stream nft's that can be fractionalized must adhere to all the following criteria's
            // 1. the sender should be the streamCreator
            // 2. the asset should be shell address
            // 3. the end time should be the streamEndTime
            // 4. the stream should be non-cancellable
            if (lockupLinear.getSender(uint256(tokenId)) != streamCreator || lockupLinear.getAsset(uint256(tokenId)) != shell || lockupLinear.getEndTime(uint256(tokenId)) != streamEndTime || lockupLinear.isCancelable(uint256(tokenId))) {
                revert INVALID_VESTING_STREAM();
            }

            // unwrap the nft
            unwrapERC721(uint256(tokenId));

            // withdraw underlying tokens from the stream
            _withdrawMax(uint256(tokenId), user);

            // wrap the nft again
            wrapERC721(uint256(tokenId));

            // set the fungible amount to mint as the remaining underlying amount that is still vesting
            outputAmount = lockupLinear.getDepositedAmount(uint256(tokenId)) - lockupLinear.getWithdrawnAmount(uint256(tokenId));
            fungibleTokenSupply += outputAmount;
        } else if (inputToken == fungibleTokenId && outputToken == nftOceanId) {
            // revert if the total underlying amount isn't the input amount
            uint256 _totalUnderlyingTokenAmount = lockupLinear.getDepositedAmount(uint256(tokenId)) - lockupLinear.getWithdrawnAmount(uint256(tokenId));

            if (_totalUnderlyingTokenAmount != inputAmount) revert INVALID_AMOUNT();

            fungibleTokenSupply -= inputAmount;

            outputAmount = 1;
        } else {
            revert("Invalid input and output tokens");
        }
    }

    /**
     * @notice
     *   Calculates the input amount for a specified output amount
     *
     *   @param inputToken Input token id
     *   @param outputToken Output token id
     *   @param outputAmount Output token amount
     *   @param tokenId erc721 token id.
     *
     *   @return inputAmount Input amount
     */
    function computeInputAmount(uint256 inputToken, uint256 outputToken, uint256 outputAmount, address user, bytes32 tokenId) external override onlyOcean returns (uint256 inputAmount) {
        uint256 nftOceanId = _calculateOceanId(address(lockupLinear), uint256(tokenId));
        if (inputToken == fungibleTokenId && outputToken == nftOceanId) {
            if (outputAmount != 1) revert INVALID_AMOUNT();

            uint256 _withdrawableAmount = lockupLinear.getDepositedAmount(uint256(tokenId)) - lockupLinear.getWithdrawnAmount(uint256(tokenId));

            inputAmount = _withdrawableAmount;
            fungibleTokenSupply -= inputAmount;
        } else {
            revert();
        }
    }
    /**
     * @notice
     *   Get total fungible supply
     *
     *   @param tokenId Fungible token id
     *   @return totalSupply Current total supply.
     */

    function getTokenSupply(uint256 tokenId) external view override returns (uint256 totalSupply) {
        if (tokenId != fungibleTokenId) revert INVALID_TOKEN_ID();
        totalSupply = fungibleTokenSupply;
    }

    /**
     * @notice
     *   Get Ocean token id
     *
     *   @param tokenContract NFT collection contract
     *   @return tokenId erc721 token id.
     */
    function _calculateOceanId(address tokenContract, uint256 tokenId) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(tokenContract, tokenId)));
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
     * @dev Handles the receipt of a single ERC1155 token type. This function is
     * called at the end of a `safeTransferFrom` after the balance has been updated.
     * @return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` if transfer is allowed
     */
    function onERC1155Received(address, address, uint256, uint256, bytes memory) public pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC721Received(address, address, uint256, bytes calldata) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
