// // SPDX-License-Identifier: AGPL-3.0
// pragma solidity ^0.8.18;

// import '@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol';
// import '@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol';
// import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
// import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
// import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

// import "../../integrations/merchantMoe/IMoePair.sol";
// import "../../integrations/merchantMoe/IMoeFactory.sol";
// import "../../integrations/merchantMoe/IMoeRouter.sol";

// abstract contract MoeMerchantWithOracleStrategyHelper {
//     using FixedPoint for *;

//     error MissingHistoricalObservation();
//     error UnexpectedTimeElapsed();
//     error TooLittleGranularity(uint256 granularity);
//     error WindowNotEvenlyDivisible();
//     error InvalidRatioToAddAsLiquidity(uint256 amountA, uint256 amountB);

//     struct RemoveLiquidityData {
//         uint256 amountAWithdrawn;
//         uint256 amountBWithdrawn;
//     }

//     struct Observation {
//         uint256 timestamp;
//         uint256 price0Cumulative;
//         uint256 price1Cumulative;
//     }

//     IMoeRouter public constant MOE_ROUTER =
//         IMoeRouter(0xeaEE7EE68874218c3558b40063c42B82D3E7232a);
//     IMoeFactory public constant MOE_FACTORY =
//         IMoeFactory(0x5bEf015CA9424A7C07B68490616a4C1F094BEdEc);

//     uint256 private constant MAX_BPS = 10000;
    
//     // the desired amount of time over which the moving average should be computed, e.g. 24 hours
//     uint256 public immutable windowSize;
//     // the number of observations stored for each pair, i.e. how many price observations are stored for the window.
//     // as granularity increases from 1, more frequent updates are needed, but moving averages become more precise.
//     // averages are computed over intervals with sizes in the range:
//     //   [windowSize - (windowSize / granularity) * 2, windowSize]
//     // e.g. if the window size is 24 hours, and the granularity is 24, the oracle will return the average price for
//     //   the period:
//     //   [now - [22 hours, 24 hours], now]
//     uint8 public immutable granularity;
//     // this is redundant with granularity and windowSize, but stored for gas savings & informational purposes.
//     uint256 public immutable periodSize;

//     // mapping from pair address to a list of price observations of that pair
//     mapping(address => Observation[]) public pairObservations;

//     function _initializeMoeMerchantHelperWithOracle(uint256 windowSize_, uint8 granularity_) internal {
//         if (granularity_ <= 1) {
//             revert TooLittleGranularity(granularity_);
//         }
//         if ((periodSize = windowSize_ / granularity_) * granularity_ != windowSize_) {
//             revert WindowNotEvenlyDivisible();
//         }
//         windowSize = windowSize_;
//         granularity = granularity_;
//     }

//     // returns the index of the observation corresponding to the given timestamp
//     function observationIndexOf(uint256 timestamp) public view returns (uint8 index) {
//         uint256 epochPeriod = timestamp / periodSize;
//         return uint8(epochPeriod % granularity);
//     }

//     // returns the observation from the oldest epoch (at the beginning of the window) relative to the current time
//     function getFirstObservationInWindow(address pair) private view returns (Observation storage firstObservation) {
//         uint8 observationIndex = observationIndexOf(block.timestamp);
//         // no overflow issue. if observationIndex + 1 overflows, result is still zero.
//         uint8 firstObservationIndex = (observationIndex + 1) % granularity;
//         firstObservation = pairObservations[pair][firstObservationIndex];
//     }

//     // update the cumulative price for the observation at the current timestamp. each observation is updated at most
//     // once per epoch period.
//     function _update(address tokenA, address tokenB) internal {
//         address pair = UniswapV2Library.pairFor(MOE_FACTORY, tokenA, tokenB);

//         // populate the array with empty observations (first call only)
//         for (uint256 i = pairObservations[pair].length; i < granularity; i++) {
//             pairObservations[pair].push();
//         }

//         // get the observation for the current period
//         uint8 observationIndex = observationIndexOf(block.timestamp);
//         Observation storage observation = pairObservations[pair][observationIndex];

//         // we only want to commit updates once per period (i.e. windowSize / granularity)
//         uint256 timeElapsed = block.timestamp - observation.timestamp;
//         if (timeElapsed > periodSize) {
//             (uint256 price0Cumulative, uint256 price1Cumulative,) = UniswapV2OracleLibrary.currentCumulativePrices(pair);
//             observation.timestamp = block.timestamp;
//             observation.price0Cumulative = price0Cumulative;
//             observation.price1Cumulative = price1Cumulative;
//         }
//     }

//     // given the cumulative prices of the start and end of a period, and the length of the period, compute the average
//     // price in terms of how much amount out is received for the amount in
//     function _computeAmountOut(
//         uint256 priceCumulativeStart, uint256 priceCumulativeEnd,
//         uint256 timeElapsed, uint256 amountIn
//     ) internal pure returns (uint256 amountOut) {
//         // overflow is desired.
//         FixedPoint.uq112x112 memory priceAverage = FixedPoint.uq112x112(
//             uint224((priceCumulativeEnd - priceCumulativeStart) / timeElapsed)
//         );
//         amountOut = (priceAverage * amountIn).decode144();
//     }

//     // returns the amount out corresponding to the amount in for a given token using the moving average over the time
//     // range [now - [windowSize, windowSize - periodSize * 2], now]
//     // update must have been called for the bucket corresponding to timestamp `now - windowSize`
//     function consult(address tokenIn, uint256 amountIn, address tokenOut) public view returns (uint256 amountOut) {
//         address pair = UniswapV2Library.pairFor(MOE_FACTORY, tokenIn, tokenOut);
//         Observation storage firstObservation = getFirstObservationInWindow(pair);

//         uint256 timeElapsed = block.timestamp - firstObservation.timestamp;
//         if (timeElapsed > windowSize) {
//             revert MissingHistoricalObservation();
//         }
//         // should never happen.
//         if (timeElapsed < windowSize - periodSize * 2) {
//             revert UnexpectedTimeElapsed();
//         }
        
//         (uint256 price0Cumulative, uint256 price1Cumulative,) = UniswapV2OracleLibrary.currentCumulativePrices(pair);
//         (address token0,) = UniswapV2Library.sortTokens(tokenIn, tokenOut);

//         if (token0 == tokenIn) {
//             return _computeAmountOut(firstObservation.price0Cumulative, price0Cumulative, timeElapsed, amountIn);
//         } else {
//             return _computeAmountOut(firstObservation.price1Cumulative, price1Cumulative, timeElapsed, amountIn);
//         }
//     }

//     function _moeMerchantSwap(
//         address from,
//         address to,
//         uint256 amount,
//         uint256 amountOutMin
//     ) internal returns (uint256 result) {
//         address[] memory path = new address[](2);
//         path[0] = from;
//         path[1] = to;
//         result = MOE_ROUTER.swapExactTokensForTokens(
//             amount,
//             amountOutMin,
//             path,
//             address(this),
//             block.timestamp
//         )[1];
//     }

//     function _moeMerchantAddLiquiditySingle(
//         address tokenA,
//         address tokenB,
//         uint256 amountA,
//         uint256 reserve0,
//         uint256 reserve1,
//         uint256 slippageBps
//     ) internal returns (uint256 lpMinted) {
//         uint256 tokensAToAdd = amountA / 2;
//         uint256 tokensBToAdd = MOE_ROUTER.quote(
//             tokensAToAdd,
//             reserve0,
//             reserve1
//         );
//         uint256 tokensBToAddWithSlippage = (tokensBToAdd * slippageBps) /
//             MAX_BPS;
//         uint256 swappedTokensB = _moeMerchantSwap(
//             tokenA,
//             tokenB,
//             tokensAToAdd,
//             tokensBToAddWithSlippage
//         );

//         (, , lpMinted) = MOE_ROUTER.addLiquidity(
//             tokenA,
//             tokenB,
//             tokensAToAdd,
//             swappedTokensB,
//             (tokensAToAdd * slippageBps) / MAX_BPS,
//             tokensBToAddWithSlippage,
//             address(this),
//             block.timestamp
//         );
//     }

//     function _moeMerchantAddLiquidity(
//         address tokenA,
//         address tokenB,
//         uint256 amountA, // any amount (even violating the ratio in the reserves)
//         uint256 amountB, // any amount (even violating the ratio in the reserves)
//         uint256 reserve0,
//         uint256 reserve1,
//         uint256 slippageBps
//     )
//         internal
//         returns (uint256 lpMinted, uint256 tokensALeft, uint256 tokensBLeft)
//     {
//         uint256 expectedAmountB = MOE_ROUTER.quote(amountA, reserve0, reserve1);
//         if (amountB > expectedAmountB) {
//             (, , lpMinted) = MOE_ROUTER.addLiquidity(
//                 tokenA,
//                 tokenB,
//                 amountA,
//                 expectedAmountB,
//                 (amountA * slippageBps) / MAX_BPS,
//                 (expectedAmountB * slippageBps) / MAX_BPS,
//                 address(this),
//                 block.timestamp
//             );
//             tokensBLeft = amountB - expectedAmountB;
//         } else if (
//             amountB < expectedAmountB
//         ) {
//             uint256 expectedAmountA = MOE_ROUTER.quote(amountB, reserve1, reserve0);
//             if (amountA > expectedAmountA) {
//                 (, , lpMinted) = MOE_ROUTER.addLiquidity(
//                     tokenA,
//                     tokenB,
//                     expectedAmountA,
//                     amountB,
//                     (expectedAmountA * slippageBps) / MAX_BPS,
//                     (amountB * slippageBps) / MAX_BPS,
//                     address(this),
//                     block.timestamp
//                 );
//                 tokensALeft = amountA - expectedAmountA;
//             } else {
//                 revert InvalidRatioToAddAsLiquidity(amountA, amountB);
//             }
//         } else {
//             (, , lpMinted) = MOE_ROUTER.addLiquidity(
//                 tokenA,
//                 tokenB,
//                 amountA,
//                 amountB,
//                 (amountA * slippageBps) / MAX_BPS,
//                 (amountB * slippageBps) / MAX_BPS,
//                 address(this),
//                 block.timestamp
//             );
//         }
//     }

//     function _moeMerchantRemoveLiquidity(
//         address tokenA,
//         address tokenB,
//         uint256 amountLp
//     ) internal returns (RemoveLiquidityData memory result) {
//         IMoePair(MOE_FACTORY.getPair(tokenA, tokenB)).approve(
//             address(MOE_ROUTER),
//             amountLp
//         );
//         (result.amountAWithdrawn, result.amountBWithdrawn) = MOE_ROUTER
//             .removeLiquidity(
//                 tokenA,
//                 tokenB,
//                 amountLp,
//                 0, // any amount acceptible
//                 0, // any amount acceptible
//                 address(this),
//                 block.timestamp
//             );
//     }

//     /**
//      * @dev This empty reserved space is put in place to allow future versions to add new
//      * variables without shifting down storage in the inheritance chain.
//      * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
//      */
//     uint256[45] private __gap;
// }
