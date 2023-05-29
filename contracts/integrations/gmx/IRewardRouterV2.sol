// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

interface IRewardRouterV2 {
    function stakeGmx(uint256 _amount) external;

    function compound() external;

    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external;
}
