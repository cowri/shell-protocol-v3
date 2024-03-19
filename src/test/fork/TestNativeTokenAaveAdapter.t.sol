pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/Interactions.sol";
import "../../ocean/Ocean.sol";
import "../../adapters/AaveLendAdapter.sol";

contract TestNativeTokenAaveAdapter is Test {
    address wallet = 0xC3E5607Cd4ca0D5Fe51e09B60Ed97a0Ae6F874dd;
    address lpWallet = 0xD3F0325F9aE1790dD83E76A3Bf4379fB6760DdF3;
    address dataProvider = 0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654;

    AaveLendAdapter adapter;
    address aToken = 0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8; // aweth address
    address tokenAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    Ocean ocean;

    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc"); // Will start on latest block by default
        ocean = new Ocean("");
        adapter = new AaveLendAdapter(
            address(ocean), 0x794a61358D6845594F94dc1DB02A252b5b4814aD, tokenAddress, IWETHGateway(0xB5Ee21786D28c5Ba61661550879475976B707099), IDataProvider(dataProvider), IWETH(tokenAddress)
        );
    }

    function testDeposit(uint256 amount, uint256 unwrapFee) public {
        vm.startPrank(wallet);

        // taking decimals into account
        amount = bound(amount, 1e17, IERC20(tokenAddress).balanceOf(wallet));

        IERC20(tokenAddress).approve(address(ocean), amount);

        uint256 prevInputBalance = IERC20(tokenAddress).balanceOf(wallet);
        uint256 prevOutputBalance = IERC20(aToken).balanceOf(wallet);

        Interaction[] memory interactions = new Interaction[](3);

        interactions[0] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(tokenAddress, uint256(InteractionType.WrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(0) });

        interactions[1] = Interaction({
            interactionTypeAndAddress: _fetchInteractionId(address(adapter), uint256(InteractionType.ComputeOutputAmount)),
            inputToken: _calculateOceanId(tokenAddress),
            outputToken: _calculateOceanId(aToken),
            specifiedAmount: type(uint256).max,
            metadata: bytes32(0)
        });

        interactions[2] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(aToken, uint256(InteractionType.UnwrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: type(uint256).max, metadata: bytes32(0) });

        // erc1155 token id's for balance delta
        uint256[] memory ids = new uint256[](2);
        ids[0] = _calculateOceanId(tokenAddress);
        ids[1] = _calculateOceanId(aToken);

        ocean.doMultipleInteractions(interactions, ids);

        uint256 newInputBalance = IERC20(tokenAddress).balanceOf(wallet);
        uint256 newOutputBalance = IERC20(aToken).balanceOf(wallet);

        assertLt(newInputBalance, prevInputBalance);
        assertGt(newOutputBalance, prevOutputBalance);

        vm.stopPrank();
    }

    function testWithdraw(uint256 amount, uint256 unwrapFee) public {
        amount = bound(amount, 1e17, 1e20);

        vm.prank(lpWallet);
        IERC20(aToken).approve(address(ocean), amount);

        uint256 prevInputBalance = IERC20(aToken).balanceOf(lpWallet);
        uint256 prevOutputBalance = IERC20(tokenAddress).balanceOf(lpWallet);

        Interaction[] memory interactions = new Interaction[](3);

        interactions[0] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(aToken, uint256(InteractionType.WrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(0) });

        interactions[1] = Interaction({
            interactionTypeAndAddress: _fetchInteractionId(address(adapter), uint256(InteractionType.ComputeOutputAmount)),
            inputToken: _calculateOceanId(aToken),
            outputToken: _calculateOceanId(tokenAddress),
            specifiedAmount: type(uint256).max,
            metadata: bytes32(0)
        });

        interactions[2] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(tokenAddress, uint256(InteractionType.UnwrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: type(uint256).max, metadata: bytes32(0) });

        // erc1155 token id's for balance delta
        uint256[] memory ids = new uint256[](2);
        ids[0] = _calculateOceanId(aToken);
        ids[1] = _calculateOceanId(tokenAddress);

        vm.prank(lpWallet);
        ocean.doMultipleInteractions(interactions, ids);

        uint256 newInputBalance = IERC20(aToken).balanceOf(lpWallet);
        uint256 newOutputBalance = IERC20(tokenAddress).balanceOf(lpWallet);

        assertLt(newInputBalance, prevInputBalance);
        assertGt(newOutputBalance, prevOutputBalance);
        // assertEq(newOutputBalance - prevOutputBalance, prevInputBalance - newInputBalance);

    }
  
    function _calculateOceanId(address token) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(token, uint256(0))));
    }

    function _fetchInteractionId(address token, uint256 interactionType) internal pure returns (bytes32) {
        uint256 packedValue = uint256(uint160(token));
        packedValue |= interactionType << 248;
        return bytes32(abi.encode(packedValue));
    }
}
