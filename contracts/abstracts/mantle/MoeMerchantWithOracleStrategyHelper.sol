// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "@uniswap/lib/contracts/libraries/FixedPoint.sol";

import "../../strategies/mantle/libraries/MoeMerchantLib.sol";
import "./StrategyHelper.sol";

abstract contract MoeMerchantWithOracleStrategyHelper is StrategyHelper {
    using FixedPoint for *;

    error WindowHasNotElapsed(uint256 remainingTimeInSecs);
    error NoObservationsFor(address tokenIn);

    event ObservationsUpdated(
        address indexed pair,
        uint256 indexed lastPrice0Cumulative,
        uint256 indexed lastPrice1Cumulative,
        uint32 lastBlockTimestamp,
        FixedPoint.uq112x112 price0Average,
        FixedPoint.uq112x112 price1Average
    );

    struct Observations {
        uint256 lastPrice0Cumulative;
        uint256 lastPrice1Cumulative;
        uint32 lastBlockTimestamp;
        FixedPoint.uq112x112 price0Average;
        FixedPoint.uq112x112 price1Average;
    }

    mapping(address pair => Observations observations)
        public getPairObservations;

    uint256 public windowSize;

    function _setWindowSize(uint256 newWindowSize) internal {
        windowSize = newWindowSize;
    }

    function update(address tokenA, address tokenB) external onlySelf {
        address pair = MoeMerchantLib.MOE_FACTORY.getPair(tokenA, tokenB);
        Observations storage pairObservations = getPairObservations[pair];
        if (pairObservations.lastBlockTimestamp == 0) {
            IMoePair pairInstance = IMoePair(pair);
            pairObservations.lastPrice0Cumulative = pairInstance
                .price0CumulativeLast();
            pairObservations.lastPrice1Cumulative = pairInstance
                .price1CumulativeLast();
            (, , pairObservations.lastBlockTimestamp) = pairInstance
                .getReserves();
        } else {
            (
                uint price0Cumulative,
                uint price1Cumulative,
                uint32 blockTimestamp
            ) = _currentCumulativePrices(pair);

            uint32 timeElapsed = blockTimestamp -
                pairObservations.lastBlockTimestamp; // overflow is desired
            // ensure that at least one full period has passed since the last update
            if (timeElapsed < windowSize) {
                revert WindowHasNotElapsed(windowSize - timeElapsed);
            }

            // overflow is desired, casting never truncates
            // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
            pairObservations.price0Average = FixedPoint.uq112x112(
                uint224(
                    (price0Cumulative - pairObservations.lastPrice0Cumulative) /
                        timeElapsed
                )
            );
            pairObservations.price1Average = FixedPoint.uq112x112(
                uint224(
                    (price1Cumulative - pairObservations.lastPrice1Cumulative) /
                        timeElapsed
                )
            );

            pairObservations.lastPrice0Cumulative = price0Cumulative;
            pairObservations.lastPrice1Cumulative = price1Cumulative;
            pairObservations.lastBlockTimestamp = blockTimestamp;
        }
        emit ObservationsUpdated(
            pair,
            pairObservations.lastPrice0Cumulative,
            pairObservations.lastPrice1Cumulative,
            pairObservations.lastBlockTimestamp,
            pairObservations.price0Average,
            pairObservations.price1Average
        );
    }

    // note this will always return 0 before update has been called successfully for the first time.
    function consult(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) external view returns (uint amountOut) {
        IMoePair pair = IMoePair(MoeMerchantLib.MOE_FACTORY.getPair(tokenIn, tokenOut));
        Observations storage pairObservations = getPairObservations[address(pair)];
        if (tokenIn == pair.token0()) {
            amountOut = pairObservations.price0Average.mul(amountIn).decode144();
        } else if (tokenIn == pair.token1()) {
            amountOut = pairObservations.price1Average.mul(amountIn).decode144();
        } else {
            revert NoObservationsFor(tokenIn);
        }
    }

    // helper function that returns the current block timestamp within the range of uint32, i.e. [0, 2**32 - 1]
    function _currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp % 2 ** 32);
    }

    function _currentCumulativePrices(
        address pair
    )
        internal
        view
        returns (
            uint price0Cumulative,
            uint price1Cumulative,
            uint32 blockTimestamp
        )
    {
        blockTimestamp = _currentBlockTimestamp();
        price0Cumulative = IMoePair(pair).price0CumulativeLast();
        price1Cumulative = IMoePair(pair).price1CumulativeLast();

        // if time has elapsed since the last update on the pair, mock the accumulated price values
        (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        ) = IMoePair(pair).getReserves();
        if (blockTimestampLast != blockTimestamp) {
            // subtraction overflow is desired
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;
            // addition overflow is desired
            // counterfactual
            price0Cumulative +=
                uint(FixedPoint.fraction(reserve1, reserve0)._x) *
                timeElapsed;
            // counterfactual
            price1Cumulative +=
                uint(FixedPoint.fraction(reserve0, reserve1)._x) *
                timeElapsed;
        }
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[45] private __gap;
}
