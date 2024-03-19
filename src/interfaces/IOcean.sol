// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity ^0.8.19;

import "./Interactions.sol";

interface IOcean {
    function setApprovalForAll(address, bool) external;

    function doMultipleInteractions(Interaction[] calldata interactions, uint256[] calldata ids) external payable returns (uint256[] memory, uint256[] memory, uint256[] memory, uint256[] memory);

    function balanceOf(address, uint256) external view returns (uint256);

    function WRAPPED_ETHER_ID() external view returns (uint256);
}
