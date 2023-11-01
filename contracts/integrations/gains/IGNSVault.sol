pragma solidity ^0.8.18;

interface IGNSVault {
    struct Staker {
        uint128 stakedGns; // 1e18
        uint128 debtDai; // 1e18
    }

    function harvestDai() external;

    function stakeGns(uint128 amount) external;

    function unstakeGns(uint128 _amountAmount) external;

    function stakers(address staker) external view returns (Staker memory);

    function pendingRewardDai(address staker) external view returns (uint);
}
