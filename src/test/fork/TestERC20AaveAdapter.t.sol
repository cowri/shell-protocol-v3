pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/Interactions.sol";
import "../../ocean/Ocean.sol";
import "../../adapters/AaveLendAdapter.sol";

contract TestERC20AaveAdapter is Test {
    address wallet = 0xF977814e90dA44bFA03b6295A0616a897441aceC;
    address lpWallet = 0xA2F6e6c584F7B976C5640982aF26B9BE9BEA87d3;
    address dataProvider = 0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654;
    address tokenAddress = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    AaveLendAdapter adapter;
    address aToken;
    Ocean ocean;

    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc"); // Will start on latest block by default
        vm.prank(wallet);
        ocean = new Ocean("");
        adapter = new AaveLendAdapter(
            address(ocean), 0x794a61358D6845594F94dc1DB02A252b5b4814aD, tokenAddress, IWETHGateway(0xB5Ee21786D28c5Ba61661550879475976B707099), IDataProvider(dataProvider), IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1)
        );

        (aToken,,) = IDataProvider(dataProvider).getReserveTokensAddresses(tokenAddress);
    }

    function testDeposit(uint256 amount, uint256 unwrapFee) public {
        vm.startPrank(wallet);
        unwrapFee = bound(unwrapFee, 2000, type(uint256).max);
        ocean.changeUnwrapFee(unwrapFee);

        uint256 multiplier = 1e11;

        // taking decimals into account
        amount = bound(amount, 1e17, IERC20(tokenAddress).balanceOf(wallet) * multiplier);

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
        uint256 multiplier = 1e11;

        amount = bound(amount, 1e19, IAToken(aToken).scaledBalanceOf(lpWallet) * multiplier);
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
