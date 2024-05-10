// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

import "../../integrations/agni/IAgniSwapRouter.sol";
import "../../integrations/agni/IAgniFactory.sol";

abstract contract AgniStrategyHelper {
    uint256 private constant STANDARD_SLIPPAGE = 9000;
    uint256 private constant MAX_BPS = 10000;

    IAgniSwapRouter public constant AGNI_SWAP_ROUTER =
        IAgniSwapRouter(0x319B69888b0d11cEC22caA5034e25FfFBDc88421);
    uint32 public constant AGNI_TWAP_RANGE_SECS = 1800;

    IAgniFactory public agniSwapFactory;
    uint24 public agniFee;

    function _agniStrategyHelperInitialize() internal {
        agniSwapFactory = IAgniFactory(AGNI_SWAP_ROUTER.factory());
        agniFee = 100;
    }

    function _setAgniFee(uint24 newAgniFee) internal {
        agniFee = newAgniFee;
    }

    function _agniSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256) {
        uint256 amountOutMinimum = (_agniQuote(tokenIn, tokenOut, amountIn) *
            STANDARD_SLIPPAGE) / MAX_BPS;
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

    function _agniQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            agniSwapFactory.getPool(tokenIn, tokenOut, agniFee),
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

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[45] private __gap;
}
