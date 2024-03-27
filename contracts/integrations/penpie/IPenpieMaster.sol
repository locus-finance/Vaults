// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IPenpieMaster {

    function stakingInfo(address stakingToken, address user) external view returns(uint256 stakedAmount, uint256 availableAmount);

    function multiclaimSpecPNP(address[] calldata stakingTokens, address[] memory rewardTokens, bool withPNP) external;

    function allPendingTokens(address stakingToken, address user) external view returns (uint256 pendingPenpie, address[] memory bonusTokens, string[] memory bonusTokenSymbols, uint256[] memory bonusTokenAmounts);
}


