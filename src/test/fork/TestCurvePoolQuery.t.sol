pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../adapters/query/Curve2PoolQuery.sol";

contract TestCurvePoolQuery is Test {

    Curve2PoolQuery query;

    ICurveQuery mockPool = ICurveQuery(0x1F8571544e0c94e81fE8bBea439f1aF5831f0FCd);
    ICurveQuery deployedPool = ICurveQuery(0x30dF229cefa463e991e29D42DB0bae2e122B2AC7);
    address payable adapter = payable(0xC77030692f296BC53b7995F85e6D54cb679E1115);
    
    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc");

        query = new Curve2PoolQuery(adapter, address(mockPool));
    }

    function testSwapQuery(bool toggle, uint256 amount) public {
        amount = bound(amount, 1e15, 1e22);

        uint256 balanceToken1 = deployedPool.balances(0);
        uint256 balanceToken2 = deployedPool.balances(1);
        
        SpecifiedToken inputToken;
        if (toggle) inputToken = SpecifiedToken.X;
        else inputToken = SpecifiedToken.Y;

        uint256 result = query.swapGivenInputAmount(balanceToken1, balanceToken2, amount, inputToken);
        console.log(result);
    }

    function testDepositQuery(bool toggle, uint256 amount) public {
        amount = bound(amount, 1e15, 1e22);

        uint256 balanceToken1 = deployedPool.balances(0);
        uint256 balanceToken2 = deployedPool.balances(1);

        SpecifiedToken inputToken;
        if (toggle) inputToken = SpecifiedToken.X;
        else inputToken = SpecifiedToken.Y;

        uint256 actualSupply = deployedPool.totalSupply();

        uint256 result = query.depositGivenInputAmount(balanceToken1, balanceToken2, actualSupply, amount, inputToken);
        console.log(result);
    }

    function testWithdrawQuery(bool toggle,  uint256 amount) public {        
        amount = bound(amount, 1e15, 1e20);

        uint256 balanceToken1 = deployedPool.balances(0);
        uint256 balanceToken2 = deployedPool.balances(1);
        
        SpecifiedToken inputToken;
        if (toggle) inputToken = SpecifiedToken.X;
        else inputToken = SpecifiedToken.Y;

        uint256 actualSupply = deployedPool.totalSupply();

        uint256 result = query.withdrawGivenInputAmount(balanceToken1, balanceToken2, actualSupply, amount, inputToken);
        console.log(result);
    }
}