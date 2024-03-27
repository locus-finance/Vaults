// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IPtPriceOracle {
    function getLpToAssetRate(address market, uint32 duration) external view returns(uint256 rate);

    function getPtToAssetRate(address market, uint32 duration) external view returns(uint256 rate);
}
