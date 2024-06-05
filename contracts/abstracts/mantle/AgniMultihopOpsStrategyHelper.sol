// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "../../strategies/mantle/libraries/AgniSwapLib.sol";
import "./StrategyHelper.sol";

abstract contract AgniMultihopOpsStrategyHelper is StrategyHelper {
    error SwapTraceIsNotInitialized(address fromToken, address toToken);

    struct UsdcWmntSwapParams {
        address[] fromUsdcToWmntChain;
        address[] fromWmntToUsdcChain;
        uint24[] fromUsdcToWmntFeesChain;
        uint24[] fromWmntToUsdcFeesChain;
    }

    struct UsdcWethSwapParams {
        address[] fromUsdcToWethChain;
        address[] fromWethToUsdcChain;
        uint24[] fromUsdcToWethFeesChain;
        uint24[] fromWethToUsdcFeesChain;
    }

    modifier onlyWhenUsdcWmntInitialized {
        UsdcWmntSwapParams memory _usdcWmntSwapParams = usdcWmntSwapParams;
        if (_usdcWmntSwapParams.fromUsdcToWmntChain[0] == address(0)) {
            revert SwapTraceIsNotInitialized(
                _usdcWmntSwapParams.fromUsdcToWmntChain[0],
                _usdcWmntSwapParams.fromUsdcToWmntChain[
                    _usdcWmntSwapParams.fromUsdcToWmntChain.length - 1
                ]
            );
        }
        _;
    }

    modifier onlyWhenUsdcWethInitialized {
        UsdcWethSwapParams memory _usdcWethSwapParams = usdcWethSwapParams;
        if (_usdcWethSwapParams.fromUsdcToWethChain[0] == address(0)) {
            revert SwapTraceIsNotInitialized(
                _usdcWethSwapParams.fromUsdcToWethChain[0],
                _usdcWethSwapParams.fromUsdcToWethChain[
                    _usdcWethSwapParams.fromUsdcToWethChain.length - 1
                ]
            );
        }
        _;
    }

    UsdcWmntSwapParams internal usdcWmntSwapParams;
    UsdcWethSwapParams internal usdcWethSwapParams;

    function _initializeAgniSwapStrategyHelper(
        UsdcWmntSwapParams memory _usdcWmntSwapParams,
        UsdcWethSwapParams memory _usdcWethSwapParams
    ) internal {
        usdcWmntSwapParams = _usdcWmntSwapParams;
        usdcWethSwapParams = _usdcWethSwapParams;
    }

    function usdcToWmntSwap(
        uint32 agniTwapRangeSecs,
        uint256 slippageBps,
        uint256 amountUsdc
    ) external onlySelf onlyWhenUsdcWmntInitialized returns (uint256) {
        UsdcWmntSwapParams memory _usdcWmntSwapParams = usdcWmntSwapParams;
        return
            AgniSwapLib.agniMultihopSwap(
                _usdcWmntSwapParams.fromUsdcToWmntChain,
                _usdcWmntSwapParams.fromUsdcToWmntFeesChain,
                amountUsdc,
                agniTwapRangeSecs,
                slippageBps
            );
    }

    function wmntToUsdcSwap(
        uint32 agniTwapRangeSecs,
        uint256 slippageBps,
        uint256 amountWmnt
    ) external onlySelf onlyWhenUsdcWmntInitialized returns (uint256) {
        UsdcWmntSwapParams memory _usdcWmntSwapParams = usdcWmntSwapParams;
        return
            AgniSwapLib.agniMultihopSwap(
                _usdcWmntSwapParams.fromWmntToUsdcChain,
                _usdcWmntSwapParams.fromWmntToUsdcFeesChain,
                amountWmnt,
                agniTwapRangeSecs,
                slippageBps
            );
    }

    function usdcToWmntQuote(
        uint32 agniTwapRangeSecs,
        uint256 amountUsdc
    ) public view onlyWhenUsdcWmntInitialized returns (uint256 result) {
        UsdcWmntSwapParams memory _usdcWmntSwapParams = usdcWmntSwapParams;
        result = AgniSwapLib.agniMultiswapQuote(
            _usdcWmntSwapParams.fromUsdcToWmntChain,
            _usdcWmntSwapParams.fromUsdcToWmntFeesChain,
            amountUsdc,
            agniTwapRangeSecs
        );
    }

    function wmntToUsdcQuote(
        uint32 agniTwapRangeSecs,
        uint256 amountWmnt
    ) public view onlyWhenUsdcWmntInitialized returns (uint256 result) {
        UsdcWmntSwapParams memory _usdcWmntSwapParams = usdcWmntSwapParams;
        result = AgniSwapLib.agniMultiswapQuote(
            _usdcWmntSwapParams.fromWmntToUsdcChain,
            _usdcWmntSwapParams.fromWmntToUsdcFeesChain,
            amountWmnt,
            agniTwapRangeSecs
        );
    }

    function wethToUsdcQuote(
        uint32 agniTwapRangeSecs,
        uint256 amountWeth
    ) public view onlyWhenUsdcWethInitialized returns (uint256 result) {
        UsdcWethSwapParams memory _usdcWethSwapParams = usdcWethSwapParams;
        result = AgniSwapLib.agniMultiswapQuote(
            _usdcWethSwapParams.fromWethToUsdcChain,
            _usdcWethSwapParams.fromWethToUsdcFeesChain,
            amountWeth,
            agniTwapRangeSecs
        );
    }

    function usdcToWethQuote(
        uint32 agniTwapRangeSecs,
        uint256 amountUsdc
    ) public view onlyWhenUsdcWethInitialized returns (uint256 result) {
        UsdcWethSwapParams memory _usdcWethSwapParams = usdcWethSwapParams;
        result = AgniSwapLib.agniMultiswapQuote(
            _usdcWethSwapParams.fromUsdcToWethChain,
            _usdcWethSwapParams.fromUsdcToWethFeesChain,
            amountUsdc,
            agniTwapRangeSecs
        );
    }

    function wethToUsdcSwap(
        uint32 agniTwapRangeSecs,
        uint256 slippageBps,
        uint256 amountWeth
    ) external onlySelf onlyWhenUsdcWethInitialized returns (uint256) {
        UsdcWethSwapParams memory _usdcWethSwapParams = usdcWethSwapParams;
        return
            AgniSwapLib.agniMultihopSwap(
                _usdcWethSwapParams.fromWethToUsdcChain,
                _usdcWethSwapParams.fromWethToUsdcFeesChain,
                amountWeth,
                agniTwapRangeSecs,
                slippageBps
            );
    }

    function usdcToWethSwap(
        uint32 agniTwapRangeSecs,
        uint256 slippageBps,
        uint256 amountUsdc
    ) external onlySelf onlyWhenUsdcWethInitialized returns (uint256) {
        UsdcWethSwapParams memory _usdcWethSwapParams = usdcWethSwapParams;
        return
            AgniSwapLib.agniMultihopSwap(
                _usdcWethSwapParams.fromUsdcToWethChain,
                _usdcWethSwapParams.fromUsdcToWethFeesChain,
                amountUsdc,
                agniTwapRangeSecs,
                slippageBps
            );
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[45] private __gap;
}
