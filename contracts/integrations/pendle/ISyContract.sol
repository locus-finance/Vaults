// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface ISyContract {
    function exchangeRate() external view returns(uint256);
}
