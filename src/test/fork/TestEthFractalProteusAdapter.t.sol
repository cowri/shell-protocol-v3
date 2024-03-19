pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../../interfaces/Interactions.sol";
import "../../ocean/Ocean.sol";
import "../../adapters/ProteusAdapter.sol";

contract TestEthFractalProteusAdapter is Test {
    Ocean ocean;
    address shellV2 = 0xC32eB36f886F638fffD836DF44C124074cFe3584;
    address wallet = 0x07c648648A6Bd4Ab688a1995FC049285F541FE20; // ETH+USD shLP holder
    ProteusAdapter adapter;
    uint256 xToken;
    uint256 yToken;
    uint256 lpTokenId;

    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc"); // Will start on latest block by default
        ocean = new Ocean("");
        adapter = new ProteusAdapter(address(ocean), 0xa2dB39e781A5Eee0EAA625dace6F097c17dfF7Ea, address(0x4574686572), shellV2);

        xToken = adapter.shellV2Ids(adapter.xToken());
        yToken = adapter.shellV2Ids(adapter.yToken());
        lpTokenId = adapter.shellV2Ids(adapter.lpTokenId());

        vm.prank(wallet);
        IERC1155(shellV2).setApprovalForAll(address(ocean), true);
    }

    function testSwap(bool toggle, uint256 amount) public {
        uint256 inputToken;
        uint256 outputToken;

        if (toggle) {
            inputToken = xToken;
            outputToken = yToken;
        } else {
            inputToken = yToken;
            outputToken = xToken;
        }

        // taking decimals into account
        amount = bound(amount, 1e17, toggle ? wallet.balance / 2 : IERC1155(shellV2).balanceOf(wallet, inputToken));

        uint256 prevInputBalance = toggle ? wallet.balance : IERC1155(shellV2).balanceOf(wallet, inputToken);
        uint256 prevOutputBalance = toggle ? IERC1155(shellV2).balanceOf(wallet, outputToken) : wallet.balance;

        Interaction[] memory interactions;

        uint256 etherAmount = 0;

        if (toggle) {
            etherAmount = amount;

            interactions = new Interaction[](2);

            interactions[0] = Interaction({
                interactionTypeAndAddress: _fetchInteractionId(address(adapter), uint256(InteractionType.ComputeOutputAmount)),
                inputToken: inputToken,
                outputToken: _calculateOceanId(shellV2, outputToken),
                specifiedAmount: type(uint256).max,
                metadata: bytes32(0)
            });

            interactions[1] =
                Interaction({ interactionTypeAndAddress: _fetchInteractionId(shellV2, uint256(InteractionType.UnwrapErc1155)), inputToken: 0, outputToken: 0, specifiedAmount: type(uint256).max, metadata: bytes32(outputToken) });
        } else {
            interactions = new Interaction[](3);

            interactions[0] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(shellV2, uint256(InteractionType.WrapErc1155)), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(inputToken) });

            interactions[1] = Interaction({
                interactionTypeAndAddress: _fetchInteractionId(address(adapter), uint256(InteractionType.ComputeOutputAmount)),
                inputToken: _calculateOceanId(shellV2, inputToken),
                outputToken: outputToken,
                specifiedAmount: type(uint256).max,
                metadata: bytes32(0)
            });

            interactions[2] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(address(0), uint256(InteractionType.UnwrapEther)), inputToken: 0, outputToken: 0, specifiedAmount: type(uint256).max, metadata: bytes32(0) });
        }

        // erc1155 token id's for balance delta
        uint256[] memory ids = new uint256[](2);
        ids[0] = toggle ? inputToken : _calculateOceanId(shellV2, inputToken);
        ids[1] = toggle ? _calculateOceanId(shellV2, outputToken) : outputToken;

        vm.prank(wallet);
        ocean.doMultipleInteractions{ value: etherAmount }(interactions, ids);

        uint256 newInputBalance = toggle ? wallet.balance : IERC1155(shellV2).balanceOf(wallet, inputToken);
        uint256 newOutputBalance = toggle ? IERC1155(shellV2).balanceOf(wallet, outputToken) : wallet.balance;

        assertLt(newInputBalance, prevInputBalance);
        assertGt(newOutputBalance, prevOutputBalance);
    }

    function testDeposit(bool toggle, uint256 amount) public {
        uint256 inputToken;

        if (toggle) {
            inputToken = xToken;
        } else {
            inputToken = yToken;
        }

        // taking decimals into account
        amount = bound(amount, 1e17, toggle ? wallet.balance / 2 : IERC1155(shellV2).balanceOf(wallet, inputToken));

        uint256 prevInputBalance = toggle ? wallet.balance : IERC1155(shellV2).balanceOf(wallet, inputToken);
        uint256 prevOutputBalance = IERC1155(shellV2).balanceOf(wallet, lpTokenId);

        Interaction[] memory interactions;

        uint256 etherAmount = 0;

        if (toggle) {
            etherAmount = amount;

            interactions = new Interaction[](2);

            interactions[0] = Interaction({
                interactionTypeAndAddress: _fetchInteractionId(address(adapter), uint256(InteractionType.ComputeOutputAmount)),
                inputToken: inputToken,
                outputToken: _calculateOceanId(shellV2, lpTokenId),
                specifiedAmount: type(uint256).max,
                metadata: bytes32(0)
            });

            interactions[1] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(shellV2, uint256(InteractionType.UnwrapErc1155)), inputToken: 0, outputToken: 0, specifiedAmount: type(uint256).max, metadata: bytes32(lpTokenId) });
        } else {
            interactions = new Interaction[](3);

            interactions[0] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(shellV2, uint256(InteractionType.WrapErc1155)), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(inputToken) });

            interactions[1] = Interaction({
                interactionTypeAndAddress: _fetchInteractionId(address(adapter), uint256(InteractionType.ComputeOutputAmount)),
                inputToken: _calculateOceanId(shellV2, inputToken),
                outputToken: _calculateOceanId(shellV2, lpTokenId),
                specifiedAmount: type(uint256).max,
                metadata: bytes32(0)
            });

            interactions[2] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(shellV2, uint256(InteractionType.UnwrapErc1155)), inputToken: 0, outputToken: 0, specifiedAmount: type(uint256).max, metadata: bytes32(lpTokenId) });
        }

        // erc1155 token id's for balance delta
        uint256[] memory ids = new uint256[](2);
        ids[0] = toggle ? inputToken : _calculateOceanId(shellV2, inputToken);
        ids[1] = _calculateOceanId(shellV2, lpTokenId);

        vm.prank(wallet);
        ocean.doMultipleInteractions{ value: etherAmount }(interactions, ids);

        uint256 newInputBalance = toggle ? wallet.balance : IERC1155(shellV2).balanceOf(wallet, inputToken);
        uint256 newOutputBalance = IERC1155(shellV2).balanceOf(wallet, lpTokenId);

        assertLt(newInputBalance, prevInputBalance);
        assertGt(newOutputBalance, prevOutputBalance);
    }

    function testWithdraw(bool toggle, uint256 amount) public {
        uint256 outputToken;

        if (toggle) {
            outputToken = xToken;
        } else {
            outputToken = yToken;
        }

        amount = bound(amount, 1e17, IERC1155(shellV2).balanceOf(wallet, lpTokenId));

        uint256 prevInputBalance = IERC1155(shellV2).balanceOf(wallet, lpTokenId);
        uint256 prevOutputBalance = toggle ? wallet.balance : IERC1155(shellV2).balanceOf(wallet, outputToken);

        Interaction[] memory interactions = new Interaction[](3);

        interactions[0] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(shellV2, uint256(InteractionType.WrapErc1155)), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(lpTokenId) });

        interactions[1] = Interaction({
            interactionTypeAndAddress: _fetchInteractionId(address(adapter), uint256(InteractionType.ComputeOutputAmount)),
            inputToken: _calculateOceanId(shellV2, lpTokenId),
            outputToken: toggle ? outputToken : _calculateOceanId(shellV2, outputToken),
            specifiedAmount: type(uint256).max,
            metadata: bytes32(0)
        });

        interactions[2] = Interaction({ interactionTypeAndAddress: bytes32(0), inputToken: 0, outputToken: 0, specifiedAmount: type(uint256).max, metadata: bytes32(0) });

        if (toggle) {
            interactions[2].interactionTypeAndAddress = _fetchInteractionId(address(0), uint256(InteractionType.UnwrapEther));
        } else {
            interactions[2].interactionTypeAndAddress = _fetchInteractionId(shellV2, uint256(InteractionType.UnwrapErc1155));
            interactions[2].metadata = bytes32(outputToken);
        }

        // erc1155 token id's for balance delta
        uint256[] memory ids = new uint256[](2);
        ids[0] = _calculateOceanId(shellV2, lpTokenId);
        ids[1] = toggle ? outputToken : _calculateOceanId(shellV2, outputToken);

        vm.prank(wallet);
        ocean.doMultipleInteractions(interactions, ids);

        uint256 newInputBalance = IERC1155(shellV2).balanceOf(wallet, lpTokenId);
        uint256 newOutputBalance = toggle ? wallet.balance : IERC1155(shellV2).balanceOf(wallet, outputToken);

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
