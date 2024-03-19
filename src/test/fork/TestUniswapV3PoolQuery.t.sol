pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../adapters/query/UniswapV3PoolQuery.sol";

contract TestUniswapV3PoolQuery is Test {

    UniswapV3PoolQuery query;

    address payable adapter = payable(0xe37652552379d14EE7682F0b61f5Ae1B3b183BDd);
    IQuoter quoter = IQuoter(0x8D073a51a9b074940622e42c5F3C4d08c2c6ce77);
    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc");

        query = new UniswapV3PoolQuery(adapter, quoter);
    }

    function testSwapQuery(bool toggle, uint256 amount) public {
        amount = bound(amount, 1e15, 1e22);
        SpecifiedToken inputToken;
        if (toggle) inputToken = SpecifiedToken.X;
        else inputToken = SpecifiedToken.Y;

        uint256 result = query.swapGivenInputAmount(0, 0, amount, inputToken);
        console.log(result);
    }
}