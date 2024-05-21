// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "@uniswap/lib/contracts/libraries/FixedPoint.sol";

import "../../integrations/merchantMoe/IMoePair.sol";
import "../../integrations/merchantMoe/IMoeFactory.sol";
import "../../integrations/merchantMoe/IMoeRouter.sol";

abstract contract MoeMerchantWithOracleStrategyHelper {
    using FixedPoint for *;

    error MissingHistoricalObservation();
    error UnexpectedTimeElapsed();
    error TooLittleGranularity(uint256 granularity);
    error WindowNotEvenlyDivisible();
    error InvalidRatioToAddAsLiquidity(uint256 amountA, uint256 amountB);
    error IdenticalAddresses();
    error ZeroAddress();

    struct RemoveLiquidityData {
        uint256 amountAWithdrawn;
        uint256 amountBWithdrawn;
    }

    struct Observation {
        uint256 timestamp;
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }

    IMoeRouter public constant MOE_ROUTER =
        IMoeRouter(0xeaEE7EE68874218c3558b40063c42B82D3E7232a);
    IMoeFactory public constant MOE_FACTORY =
        IMoeFactory(0x5bEf015CA9424A7C07B68490616a4C1F094BEdEc);

    uint256 private constant MAX_BPS = 10000;

    // the desired amount of time over which the moving average should be computed, e.g. 24 hours
    uint256 public windowSize;
    // the number of observations stored for each pair, i.e. how many price observations are stored for the window.
    // as granularity increases from 1, more frequent updates are needed, but moving averages become more precise.
    // averages are computed over intervals with sizes in the range:
    //   [windowSize - (windowSize / granularity) * 2, windowSize]
    // e.g. if the window size is 24 hours, and the granularity is 24, the oracle will return the average price for
    //   the period:
    //   [now - [22 hours, 24 hours], now]
    uint8 public granularity;
    // this is redundant with granularity and windowSize, but stored for gas savings & informational purposes.
    uint256 public periodSize;

    // mapping from pair address to a list of price observations of that pair
    mapping(address => Observation[]) public pairObservations;

    function _initializeMoeMerchantHelperWithOracle(
        uint256 windowSize_,
        uint8 granularity_
    ) internal {
        if (granularity_ <= 1) {
            revert TooLittleGranularity(granularity_);
        }
        if (
            (periodSize = windowSize_ / granularity_) * granularity_ !=
            windowSize_
        ) {
            revert WindowNotEvenlyDivisible();
        }
        windowSize = windowSize_;
        granularity = granularity_;
    }

    // returns the index of the observation corresponding to the given timestamp
    function observationIndexOf(
        uint256 timestamp
    ) public view returns (uint8 index) {
        uint256 epochPeriod = timestamp / periodSize;
        return uint8(epochPeriod % granularity);
    }

    // returns the observation from the oldest epoch (at the beginning of the window) relative to the current time
    function getFirstObservationInWindow(
        address pair
    ) private view returns (Observation storage firstObservation) {
        uint8 observationIndex = observationIndexOf(block.timestamp);
        // no overflow issue. if observationIndex + 1 overflows, result is still zero.
        uint8 firstObservationIndex = (observationIndex + 1) % granularity;
        firstObservation = pairObservations[pair][firstObservationIndex];
    }

    // update the cumulative price for the observation at the current timestamp. each observation is updated at most
    // once per epoch period.
    function _update(address tokenA, address tokenB) internal {
        address pair = MOE_FACTORY.getPair(tokenA, tokenB);

        // populate the array with empty observations (first call only)
        for (uint256 i = pairObservations[pair].length; i < granularity; i++) {
            pairObservations[pair].push();
        }

        // get the observation for the current period
        uint8 observationIndex = observationIndexOf(block.timestamp);
        Observation storage observation = pairObservations[pair][
            observationIndex
        ];

        // we only want to commit updates once per period (i.e. windowSize / granularity)
        uint256 timeElapsed = block.timestamp - observation.timestamp;
        if (timeElapsed > periodSize) {
            (
                uint256 price0Cumulative,
                uint256 price1Cumulative,

            ) = _currentCumulativePrices(pair);
            observation.timestamp = block.timestamp;
            observation.price0Cumulative = price0Cumulative;
            observation.price1Cumulative = price1Cumulative;
        }
    }

    // given the cumulative prices of the start and end of a period, and the length of the period, compute the average
    // price in terms of how much amount out is received for the amount in
    function _computeAmountOut(
        uint256 priceCumulativeStart,
        uint256 priceCumulativeEnd,
        uint256 timeElapsed,
        uint256 amountIn
    ) internal pure returns (uint256 amountOut) {
        // overflow is desired.
        FixedPoint.uq112x112 memory priceAverage = FixedPoint.uq112x112(
            uint224((priceCumulativeEnd - priceCumulativeStart) / timeElapsed)
        );
        amountOut = priceAverage.mul(amountIn).decode144();
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function _sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        if (tokenA == tokenB) {
            revert IdenticalAddresses();
        }
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        if (token0 == address(0)) {
            revert ZeroAddress();
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

    // returns the amount out corresponding to the amount in for a given token using the moving average over the time
    // range [now - [windowSize, windowSize - periodSize * 2], now]
    // update must have been called for the bucket corresponding to timestamp `now - windowSize`
    function consult(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) public view returns (uint256 amountOut) {
        address pair = MOE_FACTORY.getPair(tokenIn, tokenOut);
        Observation storage firstObservation = getFirstObservationInWindow(
            pair
        );

        uint256 timeElapsed = block.timestamp - firstObservation.timestamp;
        if (timeElapsed > windowSize) {
            revert MissingHistoricalObservation();
        }
        // should never happen.
        if (timeElapsed < windowSize - periodSize * 2) {
            revert UnexpectedTimeElapsed();
        }

        (
            uint256 price0Cumulative,
            uint256 price1Cumulative,

        ) = _currentCumulativePrices(pair);
        (address token0, ) = _sortTokens(tokenIn, tokenOut);

        if (token0 == tokenIn) {
            return
                _computeAmountOut(
                    firstObservation.price0Cumulative,
                    price0Cumulative,
                    timeElapsed,
                    amountIn
                );
        } else {
            return
                _computeAmountOut(
                    firstObservation.price1Cumulative,
                    price1Cumulative,
                    timeElapsed,
                    amountIn
                );
        }
    }

    function _moeMerchantSwap(
        address from,
        address to,
        uint256 amount,
        uint256 slippageBps
    ) internal returns (uint256 result) {
        address[] memory path = new address[](2);
        path[0] = from;
        path[1] = to;
        uint256 amountOutMin = consult(from, amount, to);
        result = MOE_ROUTER.swapExactTokensForTokens(
            amount,
            (amountOutMin * slippageBps) / MAX_BPS,
            path,
            address(this),
            block.timestamp
        )[1];
    }

    function _moeMerchantAddLiquiditySingle(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 slippageBps
    ) internal returns (uint256 lpMinted) {
        uint256 amountB = consult(tokenA, amountA, tokenB);
        uint256 amountAToAdd = (amountA * amountA) / amountB;
        uint256 amountAToSwapToB;
        if (amountAToAdd > amountA) {
            amountAToSwapToB = (amountA * amountB) / amountA;
            amountAToAdd = amountA - amountAToSwapToB;
        } else {
            amountAToSwapToB = amountA - amountAToAdd;
        }
        uint256 amountBToAdd = _moeMerchantSwap(
            tokenA,
            tokenB,
            amountAToSwapToB,
            slippageBps
        );
        (, , lpMinted) = MOE_ROUTER.addLiquidity(
            tokenA,
            tokenB,
            amountAToAdd,
            amountBToAdd,
            (amountAToAdd * slippageBps) / MAX_BPS,
            (amountBToAdd * slippageBps) / MAX_BPS,
            address(this),
            block.timestamp
        );
    }

    function _moeMerchantAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA, // any amount (even violating the ratio in the reserves)
        uint256 amountB, // any amount (even violating the ratio in the reserves)
        uint256 slippageBps
    )
        internal
        returns (uint256 lpMinted, uint256 tokensALeft, uint256 tokensBLeft)
    {
        uint256 amountBMin =
            (consult(tokenA, amountA, tokenB) * slippageBps) /
            MAX_BPS;
        uint256 amountAMin =
            (consult(tokenB, amountB, tokenA) * slippageBps) /
            MAX_BPS;
        (uint256 amountASent, uint256 amountBSent, uint256 _lpMinted) = MOE_ROUTER.addLiquidity(
            tokenA,
            tokenB,
            amountA,
            amountB,
            amountAMin,
            amountBMin,
            address(this),
            block.timestamp
        );
        lpMinted = _lpMinted;
        if (amountA > amountASent) {
            tokensALeft = amountA - amountASent; 
        }
        if (amountB > amountBSent) {
            tokensBLeft = amountB - amountBSent; 
        }
    }

    function _moeMerchantRemoveLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountLp
    ) internal returns (RemoveLiquidityData memory result) {
        IMoePair(MOE_FACTORY.getPair(tokenA, tokenB)).approve(
            address(MOE_ROUTER),
            amountLp
        );
        (result.amountAWithdrawn, result.amountBWithdrawn) = MOE_ROUTER
            .removeLiquidity(
                tokenA,
                tokenB,
                amountLp,
                0, // any amount acceptible
                0, // any amount acceptible
                address(this),
                block.timestamp
            );
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[45] private __gap;
}
