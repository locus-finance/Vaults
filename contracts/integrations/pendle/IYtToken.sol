// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IYtToken {
    function pyIndexCurrent() external returns(uint256 rate);
}
