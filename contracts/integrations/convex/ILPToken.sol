// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface ILPToken {
    function calc_withdraw_one_coin(uint256 amount, int128 token) external view returns(uint256);
    function calc_token_amount(uint256[2] memory amounts, bool isDeposit) external view returns(uint256);
    function remove_liquidity_one_coin(uint256 amount, int128 token, uint256 min_rec) external returns (uint256);
}
