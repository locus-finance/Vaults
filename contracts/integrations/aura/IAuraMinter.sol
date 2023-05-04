// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface IAuraMinter {
    function inflationProtectionTime() external view returns (uint256);
}
