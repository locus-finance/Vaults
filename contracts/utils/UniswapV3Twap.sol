// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

library UniswapV3TwapGetter {
    function getSqrtTwapX96(
        address uniswapV3Pool,
        uint32 twapInterval
    ) internal view returns (uint160 sqrtPriceX96) {
        if (twapInterval == 0) {
            // return the current price if twapInterval == 0
            (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(uniswapV3Pool).slot0();
        } else {
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = twapInterval; // from (before)
            secondsAgos[1] = 0; // to (now)

            (int56[] memory tickCumulatives, ) = IUniswapV3Pool(uniswapV3Pool)
                .observe(secondsAgos);

            // tick(imprecise as it's an integer) to price
            sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
                int24(
                    (tickCumulatives[1] - tickCumulatives[0]) /
                        int56(uint56(twapInterval))
                )
            );
        }
    }

    function getPriceX96FromSqrtPriceX96(
        uint160 sqrtPriceX96
    ) internal pure returns (uint256 priceX96) {
        return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
    }

    function getTwap(
        address uniswapV3Pool,
        uint32 twapInterval
    ) internal view returns (uint256) {
        return uint256(getSqrtTwapX96(uniswapV3Pool, twapInterval));
    }
}
