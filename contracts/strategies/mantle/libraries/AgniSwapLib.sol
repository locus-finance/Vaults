// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import "../../../integrations/agni/IAgniSwapRouter.sol";
import "../../../integrations/agni/IAgniFactory.sol";

library AgniSwapLib {
    error MustBeLess(uint256 whatShouldBeLess, uint256 actual);

    uint256 private constant MAX_BPS = 10000;
    IAgniSwapRouter public constant AGNI_SWAP_ROUTER =
        IAgniSwapRouter(0x319B69888b0d11cEC22caA5034e25FfFBDc88421);
    IAgniFactory public constant AGNI_SWAP_FACTORY =
        IAgniFactory(0x25780dc8Fc3cfBD75F33bFDAB65e969b603b2035);

    function agniSwapSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 slippageBps,
        uint24 agniFee,
        uint32 twapRangeSecs
    ) internal returns (uint256) {
        uint256 amountOutMinimum = (agniQuote(
            tokenIn,
            tokenOut,
            amountIn,
            agniFee,
            twapRangeSecs
        ) * slippageBps) / MAX_BPS;
        IAgniSwapRouter.ExactInputSingleParams memory params = IAgniSwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: agniFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            });
        return AGNI_SWAP_ROUTER.exactInputSingle(params);
    }

    function agniMultihopSwap(
        address[] memory tokensChain,
        uint24[] memory tokensFeesChain,
        uint256 amountIn,
        uint32 twapRangeSecs,
        uint256 slippageBps
    ) internal returns (uint256) {
        uint256 amountOutMin = (agniMultiswapQuote(
            tokensChain,
            tokensFeesChain,
            amountIn,
            twapRangeSecs
        ) * slippageBps) / MAX_BPS;
        bytes memory path = abi.encodePacked(tokensChain[0]);
        for (uint256 i = 1; i < tokensChain.length; i++) {
            path = abi.encodePacked(
                path,
                tokensFeesChain[i - 1],
                tokensChain[i]
            );
        }
        IAgniSwapRouter.ExactInputParams memory params = IAgniSwapRouter
            .ExactInputParams({
                path: path,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin
            });
        return AGNI_SWAP_ROUTER.exactInput(params);
    }

    function _getQuoteAtTick(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        int24 meanTick
    ) internal pure returns (uint256) {
        return
            OracleLibrary.getQuoteAtTick(
                meanTick,
                uint128(amountIn),
                tokenIn,
                tokenOut
            );
    }

    function agniMultiswapQuote(
        address[] memory tokensChain,
        uint24[] memory tokensFeesChain,
        uint256 amountIn,
        uint32 twapRangeSecs
    ) internal view returns (uint256) {
        if (
            tokensChain.length <= tokensFeesChain.length ||
            tokensChain.length - tokensFeesChain.length != 1
        ) {
            revert MustBeLess(tokensFeesChain.length, tokensChain.length);
        }
        int24[] memory inBetweenTicks = new int24[](tokensFeesChain.length);
        for (uint256 i; i < inBetweenTicks.length; i++) {
            (inBetweenTicks[i], ) = OracleLibrary.consult(
                AGNI_SWAP_FACTORY.getPool(
                    tokensChain[i],
                    tokensChain[i + 1],
                    tokensFeesChain[i]
                ),
                twapRangeSecs
            );
        }
        int256 syntheticTick = OracleLibrary.getChainedPrice(
            tokensChain,
            inBetweenTicks
        );
        return
            _getQuoteAtTick(
                tokensChain[0],
                tokensChain[tokensChain.length - 1],
                amountIn,
                SafeCastUpgradeable.toInt24(syntheticTick)
            );
    }

    function agniQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint24 agniFee,
        uint32 twapRangeSecs
    ) internal view returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            AGNI_SWAP_FACTORY.getPool(tokenIn, tokenOut, agniFee),
            twapRangeSecs
        );
        return _getQuoteAtTick(tokenIn, tokenOut, amountIn, meanTick);
    }
}
