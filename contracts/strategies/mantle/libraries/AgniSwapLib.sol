// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

import "../../../integrations/agni/IAgniSwapRouter.sol";
import "../../../integrations/agni/IAgniFactory.sol";

library AgniSwapLib {
    uint256 private constant MAX_BPS = 10000;
    IAgniSwapRouter public constant AGNI_SWAP_ROUTER =
        IAgniSwapRouter(0x319B69888b0d11cEC22caA5034e25FfFBDc88421);
    uint32 public constant AGNI_TWAP_RANGE_SECS = 1800;
    IAgniFactory public constant AGNI_SWAP_FACTORY = IAgniFactory(0x25780dc8Fc3cfBD75F33bFDAB65e969b603b2035);

    function agniSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 slippageBps,
        uint24 agniFee
    ) internal returns (uint256) {
        uint256 amountOutMinimum = (agniQuote(tokenIn, tokenOut, amountIn, agniFee) *
            slippageBps) / MAX_BPS;
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

    function agniQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint24 agniFee
    ) internal view returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            AGNI_SWAP_FACTORY.getPool(tokenIn, tokenOut, agniFee),
            AGNI_TWAP_RANGE_SECS
        );
        return
            OracleLibrary.getQuoteAtTick(
                meanTick,
                uint128(amountIn),
                tokenIn,
                tokenOut
            );
    }
}
