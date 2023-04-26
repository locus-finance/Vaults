// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IGNSStakingV6_2 {
    function distributeRewardDai(uint amount) external;

    function pendingRewardDai() external view returns (uint);

    function harvest() external;

    function stakeTokens(uint amount) external;

    function unstakeTokens(uint amount) external;
}
