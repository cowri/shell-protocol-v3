// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAsset {
// solhint-disable-previous-line no-empty-blocks
}

interface IBalancerQueries {
    function queryExit(bytes32 poolId, address sender, address recipient, IBalancerVault.ExitPoolRequest memory request) external returns (uint256 bptIn, uint256[] memory amountsOut);
}

interface IPool {
    function getBptIndex() external view returns (uint256);

    function getPoolId() external view returns (bytes32);

    function getAmplificationParameter() external view returns (uint256, bool, uint256);

    function getScalingFactors() external view returns (uint256[] memory);
}

interface IBalancerVault {
    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    enum PoolSpecialization {
        GENERAL,
        MINIMAL_SWAP_INFO,
        TWO_TOKEN
    }

    function getPoolTokens(bytes32 poolId) external view returns (IERC20[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);

    function getPool(bytes32 poolId) external view returns (address, PoolSpecialization);

    function joinPool(bytes32 poolId, address sender, address recipient, JoinPoolRequest memory request) external payable;

    struct JoinPoolRequest {
        IAsset[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    function exitPool(bytes32 poolId, address sender, address payable recipient, ExitPoolRequest memory request) external;

    struct ExitPoolRequest {
        IAsset[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    function swap(SingleSwap memory singleSwap, FundManagement memory funds, uint256 limit, uint256 deadline) external payable returns (uint256);

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        IAsset assetIn;
        IAsset assetOut;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }
}
