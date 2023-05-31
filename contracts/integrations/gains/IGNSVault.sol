pragma solidity ^0.8.18;

interface IGNSVault {
    struct User {
        uint stakedTokens;
        uint debtDai;
        uint stakedNftsCount;
        uint totalBoostTokens;
        uint harvestedRewardsDai;
    }

    function harvest() external;

    function stakeTokens(uint amount) external;

    function unstakeTokens(uint amount) external;

    function users(address u) external view returns (User memory);

    function pendingRewardDai() external view returns (uint);
}
