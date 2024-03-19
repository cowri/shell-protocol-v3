pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../../interfaces/Interactions.sol";
import "../../ocean/Ocean.sol";
import "../../adapters/ProteusAdapter.sol";

contract TestEthProteusAdapter is Test {
    Ocean ocean;
    address shellV2 = 0xC32eB36f886F638fffD836DF44C124074cFe3584;
    address xtokenWhale = 0x60CEEf10f9dd4a5d7874f22F461048eA96f475f6;
    address ytokenWhale = 0x6D0F58fdD73a34cb012B0bA10695440CBF3f7476;
    address lpTokenWhale = 0x5BeC4A47f2E8529a27DaC5F34d0c5bc2E8064Ea0;
    address wallet = 0x916792f7734089470de27297903BED8a4630b26D;
    address erc20Address = 0x5979D7b546E38E414F7E9822514be443A4800529; // wstETH
    ProteusAdapter adapter;
    uint256 xToken;
    uint256 yToken;
    uint256 lpTokenId;

    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc"); // Will start on latest block by default
        ocean = new Ocean("");
        adapter = new ProteusAdapter(address(ocean), 0x2EaB95A938d1fAbb1b62132bDB0C5A2405a57887, erc20Address, address(0x4574686572));

        xToken = adapter.shellV2Ids(adapter.xToken());
        yToken = adapter.shellV2Ids(adapter.yToken());
        lpTokenId = adapter.shellV2Ids(adapter.lpTokenId());

        vm.prank(wallet);
        IERC1155(shellV2).setApprovalForAll(address(ocean), true);
        vm.prank(wallet);
        IERC20(erc20Address).approve(address(ocean), type(uint256).max);

        vm.startPrank(xtokenWhale);
        IERC1155(shellV2).safeTransferFrom(xtokenWhale, wallet, xToken, IERC1155(shellV2).balanceOf(xtokenWhale, xToken), new bytes(0));
        vm.stopPrank();

        vm.startPrank(ytokenWhale);
        IERC1155(shellV2).safeTransferFrom(ytokenWhale, wallet, yToken, IERC1155(shellV2).balanceOf(ytokenWhale, yToken), new bytes(0));
        vm.stopPrank();

        vm.startPrank(lpTokenWhale);
        IERC1155(shellV2).safeTransferFrom(lpTokenWhale, wallet, lpTokenId, IERC1155(shellV2).balanceOf(lpTokenWhale, lpTokenId), new bytes(0));
        vm.stopPrank();
    }

    function testSwap(bool toggle, uint256 amount) public {
        amount = bound(amount, 1e16, toggle ? IERC20(erc20Address).balanceOf(wallet) : wallet.balance / 2);

        uint256 inputToken;
        uint256 outputToken;

        if (toggle) {
            inputToken = xToken;
            outputToken = yToken;
        } else {
            inputToken = yToken;
            outputToken = xToken;
        }

        uint256 prevInputBalance = toggle ? IERC20(erc20Address).balanceOf(wallet) : wallet.balance;
        uint256 prevOutputBalance = toggle ? wallet.balance : IERC20(erc20Address).balanceOf(wallet);

        Interaction[] memory interactions;

        uint256 etherAmount = 0;

        if (toggle) {
            interactions = new Interaction[](3);

            interactions[0] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(erc20Address, uint256(InteractionType.WrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(0) });

            interactions[1] = Interaction({
                interactionTypeAndAddress: _fetchInteractionId(address(adapter), uint256(InteractionType.ComputeOutputAmount)),
                inputToken: inputToken,
                outputToken: outputToken,
                specifiedAmount: type(uint256).max,
                metadata: bytes32(0)
            });

            interactions[2] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(address(0), uint256(InteractionType.UnwrapEther)), inputToken: 0, outputToken: 0, specifiedAmount: type(uint256).max, metadata: bytes32(0) });
        } else {
            etherAmount = amount;

            interactions = new Interaction[](2);

            interactions[0] = Interaction({
                interactionTypeAndAddress: _fetchInteractionId(address(adapter), uint256(InteractionType.ComputeOutputAmount)),
                inputToken: inputToken,
                outputToken: outputToken,
                specifiedAmount: type(uint256).max,
                metadata: bytes32(0)
            });

            interactions[1] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(erc20Address, uint256(InteractionType.UnwrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: type(uint256).max, metadata: bytes32(0) });
        }

        // erc1155 token id's for balance delta
        uint256[] memory ids = new uint256[](2);
        ids[0] = inputToken;
        ids[1] = outputToken;

        vm.prank(wallet);
        ocean.doMultipleInteractions{ value: etherAmount }(interactions, ids);

        uint256 newInputBalance = toggle ? IERC20(erc20Address).balanceOf(wallet) : wallet.balance;
        uint256 newOutputBalance = toggle ? wallet.balance : IERC20(erc20Address).balanceOf(wallet);

        assertLt(newInputBalance, prevInputBalance);
        assertGt(newOutputBalance, prevOutputBalance);
    }

    function testDeposit(bool toggle, uint256 amount) public {
        amount = bound(amount, 1e16, toggle ? IERC20(erc20Address).balanceOf(wallet) : wallet.balance / 2);

        uint256 inputToken;

        if (toggle) {
            inputToken = xToken;
        } else {
            inputToken = yToken;
        }

        uint256 prevInputBalance = toggle ? IERC20(erc20Address).balanceOf(wallet) : wallet.balance;
        uint256 prevOutputBalance = IERC1155(shellV2).balanceOf(wallet, lpTokenId);

        Interaction[] memory interactions;

        uint256 etherAmount = 0;

        if (toggle) {
            interactions = new Interaction[](3);

            interactions[0] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(erc20Address, uint256(InteractionType.WrapErc20)), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(0) });

            interactions[1] = Interaction({
                interactionTypeAndAddress: _fetchInteractionId(address(adapter), uint256(InteractionType.ComputeOutputAmount)),
                inputToken: inputToken,
                outputToken: _calculateOceanId(shellV2, lpTokenId),
                specifiedAmount: type(uint256).max,
                metadata: bytes32(0)
            });

            interactions[2] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(shellV2, uint256(InteractionType.UnwrapErc1155)), inputToken: 0, outputToken: 0, specifiedAmount: type(uint256).max, metadata: bytes32(lpTokenId) });
        } else {
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
        }

        // erc1155 token id's for balance delta
        uint256[] memory ids = new uint256[](2);
        ids[0] = inputToken;
        ids[1] = _calculateOceanId(shellV2, lpTokenId);

        vm.prank(wallet);
        ocean.doMultipleInteractions{ value: etherAmount }(interactions, ids);

        uint256 newInputBalance = toggle ? IERC20(erc20Address).balanceOf(wallet) : wallet.balance;
        uint256 newOutputBalance = IERC1155(shellV2).balanceOf(wallet, lpTokenId);

        assertLt(newInputBalance, prevInputBalance);
        assertGt(newOutputBalance, prevOutputBalance);
    }

    function testWithdraw(bool toggle, uint256 amount) public {
        amount = bound(amount, 1e17, IERC1155(shellV2).balanceOf(wallet, lpTokenId));

        uint256 outputToken;

        if (toggle) {
            outputToken = xToken;
        } else {
            outputToken = yToken;
        }

        uint256 prevInputBalance = IERC1155(shellV2).balanceOf(wallet, lpTokenId);
        uint256 prevOutputBalance = toggle ? IERC20(erc20Address).balanceOf(wallet) : wallet.balance;

        Interaction[] memory interactions = new Interaction[](3);

        interactions[0] = Interaction({ interactionTypeAndAddress: _fetchInteractionId(shellV2, uint256(InteractionType.WrapErc1155)), inputToken: 0, outputToken: 0, specifiedAmount: amount, metadata: bytes32(lpTokenId) });

        interactions[1] = Interaction({
            interactionTypeAndAddress: _fetchInteractionId(address(adapter), uint256(InteractionType.ComputeOutputAmount)),
            inputToken: _calculateOceanId(shellV2, lpTokenId),
            outputToken: outputToken,
            specifiedAmount: type(uint256).max,
            metadata: bytes32(0)
        });

        interactions[2] = Interaction({ interactionTypeAndAddress: bytes32(0), inputToken: 0, outputToken: 0, specifiedAmount: type(uint256).max, metadata: bytes32(0) });

        if (toggle) {
            interactions[2].interactionTypeAndAddress = _fetchInteractionId(erc20Address, uint256(InteractionType.UnwrapErc20));
        } else {
            interactions[2].interactionTypeAndAddress = _fetchInteractionId(address(0), uint256(InteractionType.UnwrapEther));
        }

        // erc1155 token id's for balance delta
        uint256[] memory ids = new uint256[](2);
        ids[0] = _calculateOceanId(shellV2, lpTokenId);
        ids[1] = outputToken;

        vm.prank(wallet);
        ocean.doMultipleInteractions(interactions, ids);

        uint256 newInputBalance = IERC1155(shellV2).balanceOf(wallet, lpTokenId);
        uint256 newOutputBalance = toggle ? IERC20(erc20Address).balanceOf(wallet) : wallet.balance;

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
