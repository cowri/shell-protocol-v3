pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../adapters/query/Curve2PoolQuery_v2.sol";

contract TestCurvePoolQuery_v2 is Test {

    Curve2PoolQuery_v2 query;

    ICurveQuery mockPool = ICurveQuery(0xa31AD34d2300d0A4e67E6506bb54C793E9eAb003);
    ICurveQuery deployedPool = ICurveQuery(0x2FE7AE43591E534C256A1594D326e5779E302Ff4);
    address payable adapter = payable(0x7cdF1b25C74fc6562A75C86127a9ba4A650BFB9A);
    
    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc");

        query = new Curve2PoolQuery_v2(adapter, address(mockPool));
    }

    function testSwapQuery(bool toggle, uint256 amount) public {
        amount = bound(amount, 1e15, 1e22);

        uint256[] memory balances = deployedPool.get_balances();
        
        SpecifiedToken inputToken;
        if (toggle) inputToken = SpecifiedToken.X;
        else inputToken = SpecifiedToken.Y;

        uint256 result = query.swapGivenInputAmount(balances[0], balances[1], amount, inputToken);
        console.log(result);
    }

    function testDepositQuery(bool toggle, uint256 amount) public {
        amount = bound(amount, 1e15, 1e22);
        uint256[] memory balances = deployedPool.get_balances();
        
        SpecifiedToken inputToken;
        if (toggle) inputToken = SpecifiedToken.X;
        else inputToken = SpecifiedToken.Y;

        uint256 actualSupply = deployedPool.totalSupply();

        uint256 result = query.depositGivenInputAmount(balances[0], balances[1], actualSupply, amount, inputToken);
        console.log(result);
    }

    function testWithdrawQuery(bool toggle,  uint256 amount) public {        
        amount = bound(amount, 1e15, 1e20);
        uint256[] memory balances = deployedPool.get_balances();
        
        SpecifiedToken inputToken;
        if (toggle) inputToken = SpecifiedToken.X;
        else inputToken = SpecifiedToken.Y;

        uint256 actualSupply = deployedPool.totalSupply();

        uint256 result = query.withdrawGivenInputAmount(balances[0], balances[1], actualSupply, amount, inputToken);
        console.log(result);
    }
    
}

