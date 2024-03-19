pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/Interactions.sol";
import "../../ocean/Ocean.sol";
import "../../adapters/BalancerAdapter.sol";

contract TestBalancerVolatilePoolAdapter is Test {
    Ocean ocean;

    address token1Whale = 0x940a7ed683A60220dE573AB702Ec8F789ef0A402;
    address token2Whale = 0x95e62E8FF84ed8456fDc9739eE4A9597Bb6E4c1f;
    address lpWallet = 0x496b81c49902FBb624024B6f65909bAf861751fB; //bpt whale
    IBalancerVault vault = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IBalancerQueries query = IBalancerQueries(0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5);
    BalancerAdapter adapter;
    address token1 = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address token2 = 0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8;
    bytes32 poolId = 0xade4a71bb62bec25154cfc7e6ff49a513b491e81000000000000000000000497;

    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc"); // Will start on latest block by default
        ocean = new Ocean("");
        adapter = new BalancerAdapter(address(ocean), address(vault), token1, token2, 0, 2, poolId);
    }

    function testSwap(bool toggle, uint256 amount, uint256 unwrapFee) public {
        unwrapFee = bound(unwrapFee, 2000, type(uint256).max);
        ocean.changeUnwrapFee(unwrapFee);

        address wallet;
        address inputAddress;
        address outputAddress;

        if (toggle) {
            inputAddress = token1;
            outputAddress = token2;
            wallet = token1Whale;
        } else {
            inputAddress = token2;
            outputAddress = token1;
            wallet = token2Whale;
        }
        vm.startPrank(wallet);

        // taking decimals into account
        amount = bound(amount, 1e17, IERC20(inputAddress).balanceOf(wallet));

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
        unwrapFee = bound(unwrapFee, 2000, type(uint256).max);
        ocean.changeUnwrapFee(unwrapFee);

        address wallet;
        address inputAddress;

        if (toggle) {
            inputAddress = token1;
            wallet = token1Whale;
        } else {
            inputAddress = token2;
            wallet = token2Whale;
        }

        vm.startPrank(wallet);

        // taking decimals into account
        amount = bound(amount, 1e17, IERC20(inputAddress).balanceOf(wallet));

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
        ocean.changeUnwrapFee(unwrapFee);

        // toggle = false;
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
            metadata: bytes32(abi.encode(amount / 2))
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
