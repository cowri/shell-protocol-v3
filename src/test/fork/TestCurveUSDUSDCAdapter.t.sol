pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/Interactions.sol";
import "../../ocean/Ocean.sol";
import "../../adapters/Curve2PoolAdapter_v2.sol";

contract TestCurveUSDUSDCAdapter is Test {
    Ocean ocean;
    address wallet = 0x3F06B60ef62378c7C31fd6F448015Ecb83Df214a; // curve usdc whale
    address secondaryTokenWallet = 0xa656f7d2A93A6F5878AA768f24eB38Ec8C827fE2; // usdc whale
    address lpWallet = 0x6Ec10070FD98E88c2B54e30e2d36EC6fd5FfF0E6; // lp whale
    Curve2PoolAdapter_v2 adapter;
    address crvUSD = 0x498Bf2B1e120FeD3ad3D42EA2165E9b73f99C1e5;
    address usdc = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc"); // Will start on latest block by default
        ocean = new Ocean("");
        adapter = new Curve2PoolAdapter_v2(address(ocean), 0xec090cf6DD891D2d014beA6edAda6e05E025D93d); // crvUSD pool address
    }

    function testSwap(bool toggle, uint256 amount, uint256 unwrapFee) public {
        unwrapFee = bound(unwrapFee, 2000, type(uint256).max);
        ocean.changeUnwrapFee(unwrapFee);

        address inputAddress;
        address outputAddress;
        address user;
        uint256 multiplier = 1;

        if (toggle) {
            user = wallet;
            inputAddress = crvUSD;
            outputAddress = usdc;
        } else {
            user = secondaryTokenWallet;
            inputAddress = usdc;
            outputAddress = crvUSD;
            multiplier = 1e11;
        }

        vm.startPrank(user);

        // taking decimals into account
        amount = bound(amount, 1e17, IERC20(inputAddress).balanceOf(user) * multiplier);

        IERC20(inputAddress).approve(address(ocean), amount);

        uint256 prevInputBalance = IERC20(inputAddress).balanceOf(user);
        uint256 prevOutputBalance = IERC20(outputAddress).balanceOf(user);

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

        uint256 newInputBalance = IERC20(inputAddress).balanceOf(user);
        uint256 newOutputBalance = IERC20(outputAddress).balanceOf(user);

        assertLt(newInputBalance, prevInputBalance);
        assertGt(newOutputBalance, prevOutputBalance);

        vm.stopPrank();
    }

    function testDeposit(bool toggle, uint256 amount, uint256 unwrapFee) public {
        unwrapFee = bound(unwrapFee, 2000, type(uint256).max);
        ocean.changeUnwrapFee(unwrapFee);

        address inputAddress;
        address user;
        uint256 multiplier = 1;

        if (toggle) {
            user = wallet;
            inputAddress = crvUSD;
        } else {
            user = secondaryTokenWallet;
            inputAddress = usdc;
            multiplier = 1e11;
        }

        vm.startPrank(user);

        // taking decimals into account
        amount = bound(amount, 1e17, IERC20(inputAddress).balanceOf(user) * multiplier);

        address outputAddress = adapter.primitive();

        IERC20(inputAddress).approve(address(ocean), amount);

        uint256 prevInputBalance = IERC20(inputAddress).balanceOf(user);
        uint256 prevOutputBalance = IERC20(outputAddress).balanceOf(user);

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

        uint256 newInputBalance = IERC20(inputAddress).balanceOf(user);
        uint256 newOutputBalance = IERC20(outputAddress).balanceOf(user);

        assertLt(newInputBalance, prevInputBalance);
        assertGt(newOutputBalance, prevOutputBalance);

        vm.stopPrank();
    }

    function testWithdraw(bool toggle, uint256 amount, uint256 unwrapFee) public {
        unwrapFee = bound(unwrapFee, 2000, type(uint256).max);
        ocean.changeUnwrapFee(unwrapFee);

        address outputAddress;
        

        if (toggle) {
            outputAddress = crvUSD;
        } else {
            outputAddress = usdc;
        }

        address inputAddress = adapter.primitive();

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
            metadata: bytes32(0)
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
