// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;
import "./IUniswapV3Factory.sol";

// Non documented uniswap interface
interface IUniFactoryProvider {
    function factory() external view returns (IUniswapV3Factory);
}