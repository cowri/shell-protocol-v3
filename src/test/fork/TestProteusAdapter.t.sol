pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../../interfaces/Interactions.sol";
import "../../ocean/Ocean.sol";
import "../../adapters/ProteusAdapter.sol";

contract TestProteusAdapter is Test {
    Ocean ocean;
    address wallet = 0x9b64203878F24eB0CDF55c8c6fA7D08Ba0cF77E5; // USDC/USDT whale
    address lpWallet = 0x25431341A5800759268a6aC1d3CD91C029D7d9CA; // Has USDT+USDC shLP tokens
    ProteusAdapter adapter;
    address usdcAddress = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address usdtAddress = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    uint256 lpTokenId;

    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc"); // Will start on latest block by default
        ocean = new Ocean("");
        adapter = new ProteusAdapter(address(ocean), 0x0cb736ea2AD425221c368407CAAFDD323b7bDc83, usdtAddress, usdcAddress);
        lpTokenId = adapter.shellV2Ids(adapter.lpTokenId());
    }

    function testSwap(bool toggle, uint256 amount) public {
        address inputAddress;
        address outputAddress;

        if (toggle) {
            inputAddress = usdcAddress;
            outputAddress = usdtAddress;
        } else {
            inputAddress = usdtAddress;
            outputAddress = usdcAddress;
        }

        // taking decimals into account
        amount = bound(amount, 1e5, IERC20(inputAddress).balanceOf(wallet) / 10) * 1e12;

        vm.prank(wallet);
        IERC20(inputAddress).approve(address(ocean), amount);

        uint256 prevInputBalance = IERC20(inputAddress).balanceOf(wallet);
        uint256 prevOutputBalance = IERC20(outputAddress).balanceOf(wallet);

        Interaction[] memory interactions = new Interaction[](3);

        interactions[0] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(inputAddress, uint256(InteractionType.WrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(0) });

        interactions[1] = Interaction({
            interactionTypeAndAddress: _fetchInteractionId(address(adapter), uint256(InteractionType.ComputeOutputAmount)),
            inputToken: _calculateOceanId(inputAddress, 0),
            outputToken: _calculateOceanId(outputAddress, 0),
            specifiedAmount: type(uint256).max,
            metadata: bytes32(0)
        });

        interactions[2] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(outputAddress, uint256(InteractionType.UnwrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: type(uint256).max, metadata: bytes32(0) });

        // erc1155 token id's for balance delta
        uint256[] memory ids = new uint256[](2);
        ids[0] = _calculateOceanId(inputAddress, 0);
        ids[1] = _calculateOceanId(outputAddress, 0);

        vm.prank(wallet);
        ocean.doMultipleInteractions(interactions, ids);

        uint256 newInputBalance = IERC20(inputAddress).balanceOf(wallet);
        uint256 newOutputBalance = IERC20(outputAddress).balanceOf(wallet);

        assertLt(newInputBalance, prevInputBalance);
        assertGt(newOutputBalance, prevOutputBalance);
    }

    function testDeposit(bool toggle, uint256 amount) public {
        address inputAddress;

        if (toggle) {
            inputAddress = usdcAddress;
        } else {
            inputAddress = usdtAddress;
        }

        // taking decimals into account
        amount = bound(amount, 1e5, IERC20(inputAddress).balanceOf(wallet) / 10) * 1e12;

        address outputAddress = address(adapter.shellV2());

        vm.prank(wallet);
        IERC20(inputAddress).approve(address(ocean), amount);

        uint256 prevInputBalance = IERC20(inputAddress).balanceOf(wallet);
        uint256 prevOutputBalance = IERC1155(outputAddress).balanceOf(wallet, lpTokenId);

        Interaction[] memory interactions = new Interaction[](3);

        interactions[0] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(inputAddress, uint256(InteractionType.WrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(0) });

        interactions[1] = Interaction({
            interactionTypeAndAddress: _fetchInteractionId(address(adapter), uint256(InteractionType.ComputeOutputAmount)),
            inputToken: _calculateOceanId(inputAddress, 0),
            outputToken: _calculateOceanId(outputAddress, lpTokenId),
            specifiedAmount: type(uint256).max,
            metadata: bytes32(0)
        });

        interactions[2] =
            Interaction({ interactionTypeAndAddress: _fetchInteractionId(outputAddress, uint256(InteractionType.UnwrapErc1155)), inputToken: 0, outputToken: 0, specifiedAmount: type(uint256).max, metadata: bytes32(lpTokenId) });

        // erc1155 token id's for balance delta
        uint256[] memory ids = new uint256[](2);
        ids[0] = _calculateOceanId(inputAddress, 0);
        ids[1] = _calculateOceanId(outputAddress, lpTokenId);

        vm.prank(wallet);
        ocean.doMultipleInteractions(interactions, ids);

        uint256 newInputBalance = IERC20(inputAddress).balanceOf(wallet);
        uint256 newOutputBalance = IERC1155(outputAddress).balanceOf(wallet, lpTokenId);

        assertLt(newInputBalance, prevInputBalance);
        assertGt(newOutputBalance, prevOutputBalance);
    }

    function testWithdraw(bool toggle, uint256 amount) public {
        address outputAddress;

        if (toggle) {
            outputAddress = usdcAddress;
        } else {
            outputAddress = usdtAddress;
        }

        address inputAddress = address(adapter.shellV2());

        amount = bound(amount, 1e17, IERC1155(inputAddress).balanceOf(lpWallet, lpTokenId));

        vm.prank(lpWallet);
        IERC1155(inputAddress).setApprovalForAll(address(ocean), true);

        uint256 prevInputBalance = IERC1155(inputAddress).balanceOf(lpWallet, lpTokenId);
        uint256 prevOutputBalance = IERC20(outputAddress).balanceOf(lpWallet);

        Interaction[] memory interactions = new Interaction[](3);

        interactions[0] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(inputAddress, uint256(InteractionType.WrapErc1155)), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(lpTokenId) });

        interactions[1] = Interaction({
            interactionTypeAndAddress: _fetchInteractionId(address(adapter), uint256(InteractionType.ComputeOutputAmount)),
            inputToken: _calculateOceanId(inputAddress, lpTokenId),
            outputToken: _calculateOceanId(outputAddress, 0),
            specifiedAmount: type(uint256).max,
            metadata: bytes32(0)
        });

        interactions[2] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(outputAddress, uint256(InteractionType.UnwrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: type(uint256).max, metadata: bytes32(0) });

        // erc1155 token id's for balance delta
        uint256[] memory ids = new uint256[](2);
        ids[0] = _calculateOceanId(inputAddress, lpTokenId);
        ids[1] = _calculateOceanId(outputAddress, 0);

        vm.prank(lpWallet);
        ocean.doMultipleInteractions(interactions, ids);

        uint256 newInputBalance = IERC1155(inputAddress).balanceOf(lpWallet, lpTokenId);
        uint256 newOutputBalance = IERC20(outputAddress).balanceOf(lpWallet);

        assertLt(newInputBalance, prevInputBalance);
        assertGt(newOutputBalance, prevOutputBalance);
    }

    function _calculateOceanId(address tokenAddress, uint256 tokenId) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(tokenAddress, tokenId)));
    }

    function _fetchInteractionId(address token, uint256 interactionType) internal pure returns (bytes32) {
        uint256 packedValue = uint256(uint160(token));
        packedValue |= interactionType << 248;
        return bytes32(abi.encode(packedValue));
    }
}
