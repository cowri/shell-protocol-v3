pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/Interactions.sol";
import "../../ocean/Ocean.sol";
import "../../adapters/BalancerAdapter.sol";

contract TestBalancerStablePoolAdapter is Test {
    Ocean ocean;
    address wallet = 0xE68Ee8A12c611fd043fB05d65E1548dC1383f2b9; // USDC/USDT whale
    address lpWallet = 0xC93D6A85b332Aa8172989d38D5E5F7305E800D90; //bpt whale
    IBalancerVault vault = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    BalancerAdapter adapter;
    address token1 = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address token2 = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    bytes32 poolId = 0x423a1323c871abc9d89eb06855bf5347048fc4a5000000000000000000000496;

    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc"); // Will start on latest block by default
        vm.prank(wallet);
        ocean = new Ocean("");
        adapter = new BalancerAdapter(address(ocean), address(vault), token1, token2, 1, 3, poolId);
    }

    function testSwap(bool toggle, uint256 amount, uint256 unwrapFee) public {
        vm.startPrank(wallet);
        unwrapFee = bound(unwrapFee, 2000, type(uint256).max);
        ocean.changeUnwrapFee(unwrapFee);

        address inputAddress;
        address outputAddress;

        if (toggle) {
            inputAddress = token1;
            outputAddress = token2;
        } else {
            inputAddress = token2;
            outputAddress = token1;
        }

        // taking decimals into account
        amount = bound(amount, 1e17, IERC20(inputAddress).balanceOf(wallet) * 1e11);

        IERC20(inputAddress).approve(address(ocean), amount);

        uint256 prevInputBalance = IERC20(inputAddress).balanceOf(wallet);
        uint256 prevOutputBalance = IERC20(outputAddress).balanceOf(wallet);

        Interaction[] memory interactions = new Interaction[](3);

        interactions[0] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(inputAddress, uint256(InteractionType.WrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(0) });

        interactions[1] = Interaction({
            interactionTypeAndAddress: _fetchInteractionId(address(adapter), uint256(InteractionType.ComputeOutputAmount)),
            inputToken: _calculateOceanId(inputAddress),
            outputToken: _calculateOceanId(outputAddress),
            specifiedAmount: type(uint256).max,
            metadata: bytes32(0)
        });

        interactions[2] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(outputAddress, uint256(InteractionType.UnwrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: type(uint256).max, metadata: bytes32(0) });

        // erc1155 token id's for balance delta
        uint256[] memory ids = new uint256[](2);
        ids[0] = _calculateOceanId(inputAddress);
        ids[1] = _calculateOceanId(outputAddress);

        ocean.doMultipleInteractions(interactions, ids);

        uint256 newInputBalance = IERC20(inputAddress).balanceOf(wallet);
        uint256 newOutputBalance = IERC20(outputAddress).balanceOf(wallet);

        assertLt(newInputBalance, prevInputBalance);
        assertGt(newOutputBalance, prevOutputBalance);

        vm.stopPrank();
    }

    function testDeposit(bool toggle, uint256 amount, uint256 unwrapFee) public {
        vm.startPrank(wallet);
        unwrapFee = bound(unwrapFee, 2000, type(uint256).max);
        ocean.changeUnwrapFee(unwrapFee);

        address inputAddress;

        if (toggle) {
            inputAddress = token1;
        } else {
            inputAddress = token2;
        }

        // taking decimals into account
        amount = bound(amount, 1e17, IERC20(inputAddress).balanceOf(wallet) * 1e11);

        address outputAddress = address(adapter.pool());

        IERC20(inputAddress).approve(address(ocean), amount);

        uint256 prevInputBalance = IERC20(inputAddress).balanceOf(wallet);
        uint256 prevOutputBalance = IERC20(address(adapter.pool())).balanceOf(wallet);

        Interaction[] memory interactions = new Interaction[](3);

        interactions[0] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(inputAddress, uint256(InteractionType.WrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(0) });

        interactions[1] = Interaction({
            interactionTypeAndAddress: _fetchInteractionId(address(adapter), uint256(InteractionType.ComputeOutputAmount)),
            inputToken: _calculateOceanId(inputAddress),
            outputToken: _calculateOceanId(outputAddress),
            specifiedAmount: type(uint256).max,
            metadata: bytes32(0)
        });

        interactions[2] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(outputAddress, uint256(InteractionType.UnwrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: type(uint256).max, metadata: bytes32(0) });

        // erc1155 token id's for balance delta
        uint256[] memory ids = new uint256[](2);
        ids[0] = _calculateOceanId(inputAddress);
        ids[1] = _calculateOceanId(outputAddress);

        ocean.doMultipleInteractions(interactions, ids);

        uint256 newInputBalance = IERC20(inputAddress).balanceOf(wallet);
        uint256 newOutputBalance = IERC20(outputAddress).balanceOf(wallet);

        assertLt(newInputBalance, prevInputBalance);
        assertGt(newOutputBalance, prevOutputBalance);

        vm.stopPrank();
    }

    function testWithdraw(bool toggle, uint256 amount, uint256 unwrapFee) public {
        unwrapFee = bound(unwrapFee, 2000, type(uint256).max);
        vm.prank(wallet);
        ocean.changeUnwrapFee(unwrapFee);

        address outputAddress;
        if (toggle) {
            outputAddress = token1;
        } else {
            outputAddress = token2;
        }

        address inputAddress = address(adapter.pool());

        amount = bound(amount, 1e17, IERC20(inputAddress).balanceOf(lpWallet));

        vm.prank(lpWallet);
        IERC20(inputAddress).approve(address(ocean), amount);

        uint256 prevInputBalance = IERC20(inputAddress).balanceOf(lpWallet);
        uint256 prevOutputBalance = IERC20(outputAddress).balanceOf(lpWallet);

        Interaction[] memory interactions = new Interaction[](3);

        interactions[0] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(inputAddress, uint256(InteractionType.WrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(0) });

        interactions[1] = Interaction({
            interactionTypeAndAddress: _fetchInteractionId(address(adapter), uint256(InteractionType.ComputeOutputAmount)),
            inputToken: _calculateOceanId(inputAddress),
            outputToken: _calculateOceanId(outputAddress),
            specifiedAmount: type(uint256).max,
            metadata: bytes32(abi.encode(1))
        });

        interactions[2] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(outputAddress, uint256(InteractionType.UnwrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: type(uint256).max, metadata: bytes32(0) });

        // erc1155 token id's for balance delta
        uint256[] memory ids = new uint256[](2);
        ids[0] = _calculateOceanId(inputAddress);
        ids[1] = _calculateOceanId(outputAddress);

        vm.prank(lpWallet);
        ocean.doMultipleInteractions(interactions, ids);

        uint256 newInputBalance = IERC20(inputAddress).balanceOf(lpWallet);
        uint256 newOutputBalance = IERC20(outputAddress).balanceOf(lpWallet);

        assertLt(newInputBalance, prevInputBalance);
        assertGt(newOutputBalance, prevOutputBalance);
    }

    function _calculateOceanId(address tokenAddress) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(tokenAddress, uint256(0))));
    }

    function _fetchInteractionId(address token, uint256 interactionType) internal pure returns (bytes32) {
        uint256 packedValue = uint256(uint160(token));
        packedValue |= interactionType << 248;
        return bytes32(abi.encode(packedValue));
    }
}
