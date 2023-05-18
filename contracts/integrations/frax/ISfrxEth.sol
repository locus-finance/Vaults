pragma solidity ^0.8.18;
interface ISfrxEth {
    function previewRedeem(uint256 shares) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
    function syncRewards() external;
    function rewardsCycleEnd() external view returns (uint256);
    function totalAssets() external view returns (uint256);
}
