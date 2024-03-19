pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/Interactions.sol";
import "../../ocean/Ocean.sol";
import "../../adapters/WethAdapter.sol";

contract TestWethAdapter is Test {
    Ocean ocean;
    address wallet = 0x940a7ed683A60220dE573AB702Ec8F789ef0A402; // WETH whale

    address weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    WethAdapter adapter;
    uint256 xToken;
    uint256 yToken;

    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc"); // Will start on latest block by default
        ocean = new Ocean("");
        adapter = new WethAdapter(address(ocean), weth);

        xToken = adapter.xToken();
        yToken = adapter.yToken();
    }

    function testSwap(bool toggle, uint256 amount) public {
        amount = bound(amount, 1e16, toggle ? wallet.balance / 2 : IERC20(weth).balanceOf(wallet));

        uint256 inputToken;
        uint256 outputToken;

        if (toggle) {
            inputToken = xToken;
            outputToken = yToken;
        } else {
            vm.prank(wallet);
            IERC20(weth).approve(address(ocean), amount);
            inputToken = yToken;
            outputToken = xToken;
        }

        uint256 prevInputBalance = toggle ? wallet.balance : IERC20(weth).balanceOf(wallet);
        uint256 prevOutputBalance = toggle ? IERC20(weth).balanceOf(wallet) : wallet.balance;

        Interaction[] memory interactions;

        uint256 etherAmount = 0;

        if (toggle) {
            etherAmount = amount;

            interactions = new Interaction[](2);

            interactions[0] = Interaction({
                interactionTypeAndAddress: _fetchInteractionId(address(adapter), uint256(InteractionType.ComputeOutputAmount)),
                inputToken: inputToken,
                outputToken: outputToken,
                specifiedAmount: type(uint256).max,
                metadata: bytes32(0)
            });

            interactions[1] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(weth, uint256(InteractionType.UnwrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: type(uint256).max, metadata: bytes32(0) });
        } else {
            interactions = new Interaction[](3);

            interactions[0] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(weth, uint256(InteractionType.WrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(0) });

            interactions[1] = Interaction({
                interactionTypeAndAddress: _fetchInteractionId(address(adapter), uint256(InteractionType.ComputeOutputAmount)),
                inputToken: inputToken,
                outputToken: outputToken,
                specifiedAmount: type(uint256).max,
                metadata: bytes32(0)
            });

            interactions[2] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(address(0), uint256(InteractionType.UnwrapEther)), inputToken: 0, outputToken: 0, specifiedAmount: type(uint256).max, metadata: bytes32(0) });
        } 

        // erc1155 token id's for balance delta
        uint256[] memory ids = new uint256[](2);
        ids[0] = inputToken;
        ids[1] = outputToken;

        vm.prank(wallet);
        ocean.doMultipleInteractions{ value: etherAmount }(interactions, ids);

        uint256 newInputBalance = toggle ? wallet.balance : IERC20(weth).balanceOf(wallet);
        uint256 newOutputBalance = toggle ? IERC20(weth).balanceOf(wallet) : wallet.balance;

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
