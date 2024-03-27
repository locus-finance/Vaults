// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IPenpieStaking {

    function depositMarket(address market, uint256 amount) external;
}
