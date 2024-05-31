pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../ocean/Ocean.sol";
import "../../adapters/BridgeForwarder.sol";

contract TestBridgeForwarder is Test {
    BridgeForwarder adapter;

    Ocean ocean = Ocean(0x96B4f4E401cCD70Ec850C1CF8b405Ad58FD5fB7a);
    IERC20 usdc = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IERC20 aUSDC = IERC20(0x625E7708f30cA75bfd92586e17077590C60eb4cD);
    IERC20 weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 dai = IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
    address uniswapPrimitive = 0xC98675DA140B7493448B986019933483400536CE;
    address aavePrimitive = 0xE03Bc2c0D75E3f759Be67E5AfBa8C9242A7BE8B1;
    address wethPrimitive = 0x65f257A45ba85ff99DC594cab2fBB1E6CBd7797E;
    address shellEthPrimitive = 0xC32A9fC5665aFFCe85CF043472F718029577F7E0;
    uint256 shellEthLP = 0x679c61f9b15e386cac1317a2029d2c2d7f0e4bf83ff5e8ed9c0cf596366a7d1a;
    address shellV2Ocean = 0xC32eB36f886F638fffD836DF44C124074cFe3584;
    address ethUsdPrimitive = 0x97064fE13D64061496d881eb3C8058E7fe19374F;
    uint256 ethUsdLPV3 = 22_081_531_016_519_943_217_154_602_208_039_428_991_300_664_203_242_938_332_687_233_291_271_853_752_932;
    uint256 ethUsdLPV2 = 27_693_504_145_523_314_218_894_589_300_395_733_675_161_932_643_753_970_852_158_242_624_431_218_756_354;
    address user = 0x1eED63EfBA5f81D95bfe37d82C8E736b974F477b;

    uint256 public constant ethOceanId = 0x97a93559a75ccc959fc63520f07017eed6d512f74e4214a7680ec0eefb5db5b4;

    function setUp() public {
        vm.createSelectFork("https://mainnet.base.org");

        // adapter = new BridgeForwarder(address(ocean));

                    address[] memory primitives = new address[](1);
            primitives[0] = uniswapPrimitive;

            uint256[] memory ids = new uint256[](2);
            ids[0] = _calculateOceanId(address(weth), 0);
            ids[1] = _calculateOceanId(address(usdc), 0);

        bytes memory executePayload = abi.encodeWithSignature("doOceanInteraction(address,address,bytes32,address,bytes32,address[],uint256[])", address(weth), address(usdc), bytes32(0), 0xd1AE7F25ace194DF69eeF015a37C5EB9ED6b8733,
bytes32(0), primitives, ids);
        emit log("helloeee");
        emit log_bytes(executePayload);
    }

    function _calculateOceanId(address tokenAddress, uint256 tokenId) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(tokenAddress, tokenId)));
    }

    function testSwap_with_single_primitive(uint256 amount, bool primitiveToggle, bool tokenToggle) public {
        vm.startPrank(user);

        bytes32 _minOutputAmount = bytes32(0);

        if (primitiveToggle) {
            address inputToken = address(usdc);
            address outputToken = address(aUSDC);

            // taking decimals into account
            amount = bound(amount, 1e4, IERC20(usdc).balanceOf(user));
            usdc.approve(address(adapter), amount);

            address[] memory primitives = new address[](1);
            primitives[0] = aavePrimitive;

            uint256[] memory ids = new uint256[](2);
            ids[0] = _calculateOceanId(address(usdc), 0);
            ids[1] = _calculateOceanId(address(aUSDC), 0);

            adapter.doOceanInteraction(inputToken, outputToken, bytes32(0), user, _minOutputAmount, primitives, ids);
        } else {
            address[] memory primitives = new address[](1);
            primitives[0] = wethPrimitive;

            if (tokenToggle) {
                address inputToken = address(weth);
                address outputToken = address(0);
                // taking decimals into account
                amount = bound(amount, 1e17, IERC20(weth).balanceOf(user));
                weth.approve(address(adapter), amount);

                uint256[] memory ids = new uint256[](2);
                ids[0] = _calculateOceanId(address(weth), 0);
                ids[1] = ethOceanId;

                adapter.doOceanInteraction(inputToken, outputToken, bytes32(0), user, _minOutputAmount, primitives, ids);
            } else {
                address inputToken = address(0);
                address outputToken = address(weth);

                vm.deal(user, 10 ether);
                amount = bound(amount, 1e17, user.balance);

                uint256[] memory ids = new uint256[](2);
                ids[0] = ethOceanId;
                ids[1] = _calculateOceanId(address(weth), 0);

                adapter.doOceanInteraction{ value: amount }(inputToken, outputToken, bytes32(0), user, _minOutputAmount, primitives, ids);
            }
        }
        vm.stopPrank();
    }

    function testSwap_with_multiple_primitives(uint256 amount, bool swapToggle, bool nativePoolToggle, bool nativeInput) public {
        vm.startPrank(user);

        bytes32 _minOutputAmount = bytes32(0);

        if (swapToggle) {
            address inputToken = address(usdc);
            address outputToken = address(dai);

            // taking decimals into account
            amount = bound(amount, 1e4, IERC20(usdc).balanceOf(user));
            usdc.approve(address(adapter), amount);

            address[] memory primitives = new address[](3);
            primitives[0] = uniswapPrimitive;
            primitives[1] = uniswapPrimitive;

            uint256[] memory ids = new uint256[](3);
            ids[0] = _calculateOceanId(address(usdc), 0);
            ids[1] = _calculateOceanId(address(weth), 0);
            ids[2] = _calculateOceanId(address(dai), 0);

            uint256 _balanceBeforeInteraction = dai.balanceOf(user);

            adapter.doOceanInteraction(inputToken, outputToken, bytes32(0), user, _minOutputAmount, primitives, ids);

            assertGt(dai.balanceOf(user), _balanceBeforeInteraction);
        } else {
            if (nativePoolToggle) {
                if (!nativeInput) {
                    address inputToken = address(usdc);
                    address outputToken = address(ocean);

                    // taking decimals into account
                    amount = bound(amount, 1e4, IERC20(usdc).balanceOf(user));
                    usdc.approve(address(adapter), amount);

                    address[] memory primitives = new address[](3);
                    primitives[0] = uniswapPrimitive;
                    primitives[1] = wethPrimitive;
                    primitives[2] = shellEthPrimitive;

                    uint256[] memory ids = new uint256[](4);
                    ids[0] = _calculateOceanId(address(usdc), 0);
                    ids[1] = _calculateOceanId(address(weth), 0);
                    ids[2] = ethOceanId;
                    ids[3] = shellEthLP;

                    uint256 _balanceBeforeInteraction = ocean.balanceOf(user, shellEthLP);

                    adapter.doOceanInteraction(inputToken, outputToken, bytes32(shellEthLP), user, _minOutputAmount, primitives, ids);

                    assertGt(ocean.balanceOf(user, shellEthLP), _balanceBeforeInteraction);
                } else {
                    address inputToken;
                    address outputToken = address(ocean);

                    address[] memory primitives = new address[](5);
                    primitives[0] = wethPrimitive;
                    primitives[1] = uniswapPrimitive;
                    primitives[2] = uniswapPrimitive;
                    primitives[3] = wethPrimitive;
                    primitives[4] = shellEthPrimitive;

                    vm.deal(user, 10 ether);
                    amount = bound(amount, 1e17, user.balance);

                    uint256[] memory ids = new uint256[](6);
                    ids[0] = ethOceanId;
                    ids[1] = _calculateOceanId(address(weth), 0);
                    ids[2] = _calculateOceanId(address(usdc), 0);
                    ids[3] = _calculateOceanId(address(weth), 0);
                    ids[4] = ethOceanId;
                    ids[5] = shellEthLP;

                    uint256 _balanceBeforeInteraction = ocean.balanceOf(user, shellEthLP);

                    adapter.doOceanInteraction{ value: amount }(inputToken, outputToken, bytes32(shellEthLP), user, _minOutputAmount, primitives, ids);

                    assertGt(ocean.balanceOf(user, shellEthLP), _balanceBeforeInteraction);
                }
            } else {
                address inputToken = address(usdc);
                address outputToken = shellV2Ocean;

                address[] memory primitives = new address[](3);
                primitives[0] = uniswapPrimitive;
                primitives[1] = wethPrimitive;
                primitives[2] = ethUsdPrimitive;

                // taking decimals into account
                amount = bound(amount, 1e4, IERC20(usdc).balanceOf(user));
                usdc.approve(address(adapter), amount);

                uint256[] memory ids = new uint256[](4);
                ids[0] = _calculateOceanId(address(usdc), 0);
                ids[1] = _calculateOceanId(address(weth), 0);
                ids[2] = ethOceanId;
                ids[3] = ethUsdLPV3;

                uint256 _balanceBeforeInteraction = IERC1155(shellV2Ocean).balanceOf(user, ethUsdLPV2);

                adapter.doOceanInteraction(inputToken, outputToken, bytes32(ethUsdLPV2), user, _minOutputAmount, primitives, ids);

                assertGt(IERC1155(shellV2Ocean).balanceOf(user, ethUsdLPV2), _balanceBeforeInteraction);
            }
        }
        vm.stopPrank();
    }
}
