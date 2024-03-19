pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/Interactions.sol";
import "../../ocean/Ocean.sol";
import "../../adapters/PendlePTAdapter.sol";

contract TestPendlePTAdapter is Test {
    Ocean ocean;

    IPendleRouter router = IPendleRouter(0x00000000005BBB0EF59571E58418F9a4357b68A0);

    address wallet = 0xAC638F849A6b8D2734Cd11D1978bb7E9fB7A7fBE;
    address secondaryTokenWallet = 0x38f046Ae944021351CE5C2486dee3027c949858F;

    PendlePTAdapter adapter;

    address ezEth = 0x2416092f143378750bb29b79eD961ab195CcEea5;
    address ptEzEth = 0x8EA5040d423410f1fdc363379Af88e1DB5eA1C34;

    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc"); // Will start on latest block by default
        ocean = new Ocean("");
        adapter = new PendlePTAdapter(address(ocean), 0x60712e3C9136CF411C561b4E948d4d26637561e7, ezEth, router);
    }

    function testSwap(bool toggle, uint256 amount, uint256 unwrapFee) public {

        address inputAddress;
        address outputAddress;
        address user;

        if (toggle) {
            user = wallet;
            inputAddress = ezEth;
            outputAddress = ptEzEth;
        } else {
            user = secondaryTokenWallet;
            inputAddress = ptEzEth;
            outputAddress = ezEth;
        }

        vm.startPrank(user);

        // taking decimals into account
        amount = bound(amount, 1e17, 1e19);

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

    function _calculateOceanId(address tokenAddress) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(tokenAddress, uint256(0))));
    }

    function _fetchInteractionId(address token, uint256 interactionType) internal pure returns (bytes32) {
        uint256 packedValue = uint256(uint160(token));
        packedValue |= interactionType << 248;
        return bytes32(abi.encode(packedValue));
    }
}
