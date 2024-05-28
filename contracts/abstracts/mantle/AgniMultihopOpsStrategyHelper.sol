// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "../../strategies/mantle/libraries/AgniSwapLib.sol";

abstract contract AgniMultihopOpsStrategyHelper {
    error SelfSenderOnly();
    
    address[] public fromUsdcToWmntChain;
    address[] public fromWmntToUsdcChain;
    uint24[] public fromUsdcToWmntFeesChain;
    uint24[] public fromWmntToUsdcFeesChain;

    modifier onlySelf {
        if (msg.sender != address(this)) {
            revert SelfSenderOnly();
        }
        _;
    }

    function _initializeAgniSwapStrategyHelper(
        address _usdcAddress,
        address _usdtAddress,
        address _wethAddress,
        address _wmntAddress,
        uint24 _usdcUsdtAgniFee,
        uint24 _usdtWethAgniFee,
        uint24 _wethWmntAgniFee
    ) internal {
        fromUsdcToWmntChain = new address[](4);
        fromUsdcToWmntChain[0] = _usdcAddress;
        fromUsdcToWmntChain[1] = _usdtAddress;
        fromUsdcToWmntChain[2] = _wethAddress;
        fromUsdcToWmntChain[3] = _wmntAddress;

        fromUsdcToWmntFeesChain = new uint24[](3);
        fromUsdcToWmntFeesChain[0] = _usdcUsdtAgniFee;
        fromUsdcToWmntFeesChain[1] = _usdtWethAgniFee;
        fromUsdcToWmntFeesChain[2] = _wethWmntAgniFee;

        fromWmntToUsdcChain = new address[](4);
        fromWmntToUsdcChain[0] = _wmntAddress;
        fromWmntToUsdcChain[1] = _wethAddress;
        fromWmntToUsdcChain[2] = _usdtAddress;
        fromWmntToUsdcChain[3] = _usdcAddress;

        fromWmntToUsdcFeesChain = new uint24[](3);
        fromWmntToUsdcFeesChain[0] = _wethWmntAgniFee;
        fromWmntToUsdcFeesChain[1] = _usdtWethAgniFee;
        fromWmntToUsdcFeesChain[2] = _usdcUsdtAgniFee;
    }

    function usdcToWmntSwap(
        uint32 agniTwapRangeSecs,
        uint256 slippageBps,
        uint256 amountUsdc
    ) external onlySelf returns (uint256) {
        return
            AgniSwapLib.agniMultihopSwap(
                fromUsdcToWmntChain,
                fromUsdcToWmntFeesChain,
                amountUsdc,
                agniTwapRangeSecs,
                slippageBps
            );
    }

    function wmntToUsdcSwap(
        uint32 agniTwapRangeSecs,
        uint256 slippageBps,
        uint256 amountWmnt
    ) external onlySelf returns (uint256) {
        return
            AgniSwapLib.agniMultihopSwap(
                fromWmntToUsdcChain,
                fromWmntToUsdcFeesChain,
                amountWmnt,
                agniTwapRangeSecs,
                slippageBps
            );
    }

    function usdcToWmntQuote(
        uint32 agniTwapRangeSecs,
        uint256 amountUsdc
    ) public view returns (uint256 result) {
        result = AgniSwapLib.agniMultiswapQuote(
            fromUsdcToWmntChain,
            fromUsdcToWmntFeesChain,
            amountUsdc,
            agniTwapRangeSecs
        );
    }

    function wmntToUsdcQuote(
        uint32 agniTwapRangeSecs,
        uint256 amountWmnt
    ) public view returns (uint256 result) {
        result = AgniSwapLib.agniMultiswapQuote(
            fromWmntToUsdcChain,
            fromWmntToUsdcFeesChain,
            amountWmnt,
            agniTwapRangeSecs
        );
    }
}
