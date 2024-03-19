pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../adapters/query/BalancerVolatilePoolQuery.sol";

contract TestBalancerPoolQuery is Test {

    BalancerVolatilePoolQuery query;
    IBalancerVault vault;

    IBalancerQuery mockPool = IBalancerQuery(0x7416Cc1018bf6D7DE1C649AE897FB50e231C6abc);
    IBalancerQuery deployedPool = IBalancerQuery(0xadE4A71BB62bEc25154CFc7e6ff49A513B491E81);
    address payable adapter = payable(0x85482FEC354E3959c7b7fB6d99b658DB9B53A39c);
    
    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc");

        query = new BalancerVolatilePoolQuery(adapter, address(mockPool));

        vault = IBalancerVault(BalancerAdapter(adapter).primitive());
    }

    function testSwapQuery(bool toggle, uint256 amount) public {
        amount = bound(amount, 1e15, 1e22);
        (,uint256[] memory balances,) = vault.getPoolTokens(BalancerAdapter(adapter).pool().getPoolId());
        
        SpecifiedToken inputToken;
        if (toggle) inputToken = SpecifiedToken.X;
        else inputToken = SpecifiedToken.Y;

        uint256 result = query.swapGivenInputAmount(balances[0], balances[2], amount, inputToken);
        console.log(result);
    }

    function testDepositQuery(bool toggle, uint256 amount) public {
        amount = bound(amount, 1e15, 1e22);
        (,uint256[] memory balances,) = vault.getPoolTokens(BalancerAdapter(adapter).pool().getPoolId());
        
        SpecifiedToken inputToken;
        if (toggle) inputToken = SpecifiedToken.X;
        else inputToken = SpecifiedToken.Y;

        uint256 actualSupply = deployedPool.getActualSupply();

        uint256 result = query.depositGivenInputAmount(balances[0], balances[2], actualSupply, amount, inputToken);
        console.log(result);
    }

    function testWithdrawQuery(bool toggle,  uint256 amount) public {        
        amount = bound(amount, 1e15, 1e20);
        (,uint256[] memory balances,) = vault.getPoolTokens(BalancerAdapter(adapter).pool().getPoolId());
        
        SpecifiedToken inputToken;
        if (toggle) inputToken = SpecifiedToken.X;
        else inputToken = SpecifiedToken.Y;

        uint256 actualSupply = deployedPool.getActualSupply();

        uint256 result = query.withdrawGivenInputAmount(balances[0], balances[2], actualSupply, amount, inputToken);
        console.log(result);
    }
    
}

