// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "../../integrations/merchantMoe/IMoePair.sol";
import "../../integrations/merchantMoe/IMoeFactory.sol";
import "../../integrations/merchantMoe/IMoeRouter.sol";

abstract contract MoeMerchantStrategyHelper {
    error InvalidRatioToAddAsLiquidity(uint256 amountA, uint256 amountB);

    struct RemoveLiquidityData {
        uint256 amountAWithdrawn;
        uint256 amountBWithdrawn;
    }

    IMoeRouter public constant MOE_ROUTER =
        IMoeRouter(0xeaEE7EE68874218c3558b40063c42B82D3E7232a);
    IMoeFactory public constant MOE_FACTORY =
        IMoeFactory(0x5bEf015CA9424A7C07B68490616a4C1F094BEdEc);

    uint256 private constant STANDARD_SLIPPAGE = 9000;
    uint256 private constant MAX_BPS = 10000;

    function _moeMerchantSwap(
        address from,
        address to,
        uint256 amount,
        uint256 amountOutMin
    ) internal returns (uint256 result) {
        address[] memory path = new address[](2);
        path[0] = from;
        path[1] = to;
        result = MOE_ROUTER.swapExactTokensForTokens(
            amount,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        )[1];
    }

    function _moeMerchantAddLiquiditySingle(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 reserve0,
        uint256 reserve1
    ) internal returns (uint256 lpMinted) {
        uint256 tokensAToAdd = amountA / 2;
        uint256 tokensBToAdd = MOE_ROUTER.quote(
            tokensAToAdd,
            reserve0,
            reserve1
        );
        uint256 tokensBToAddWithSlippage = (tokensBToAdd * STANDARD_SLIPPAGE) /
            MAX_BPS;
        uint256 swappedTokensB = _moeMerchantSwap(
            tokenA,
            tokenB,
            tokensAToAdd,
            tokensBToAddWithSlippage
        );

        (, , lpMinted) = MOE_ROUTER.addLiquidity(
            tokenA,
            tokenB,
            tokensAToAdd,
            swappedTokensB,
            (tokensAToAdd * STANDARD_SLIPPAGE) / MAX_BPS,
            tokensBToAddWithSlippage,
            address(this),
            block.timestamp
        );
    }

    function _moeMerchantAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA, // any amount (even violating the ratio in the reserves)
        uint256 amountB, // any amount (even violating the ratio in the reserves)
        uint256 reserve0,
        uint256 reserve1
    )
        internal
        returns (uint256 lpMinted, uint256 tokensALeft, uint256 tokensBLeft)
    {
        uint256 expectedAmountB = MOE_ROUTER.quote(amountA, reserve0, reserve1);
        if (amountB > expectedAmountB) {
            (, , lpMinted) = MOE_ROUTER.addLiquidity(
                tokenA,
                tokenB,
                amountA,
                expectedAmountB,
                (amountA * STANDARD_SLIPPAGE) / MAX_BPS,
                (expectedAmountB * STANDARD_SLIPPAGE) / MAX_BPS,
                address(this),
                block.timestamp
            );
            tokensBLeft = amountB - expectedAmountB;
        } else if (
            amountB < expectedAmountB
        ) {
            uint256 expectedAmountA = MOE_ROUTER.quote(amountB, reserve1, reserve0);
            if (amountA > expectedAmountA) {
                (, , lpMinted) = MOE_ROUTER.addLiquidity(
                    tokenA,
                    tokenB,
                    expectedAmountA,
                    amountB,
                    (expectedAmountA * STANDARD_SLIPPAGE) / MAX_BPS,
                    (amountB * STANDARD_SLIPPAGE) / MAX_BPS,
                    address(this),
                    block.timestamp
                );
                tokensALeft = amountA - expectedAmountA;
            } else {
                revert InvalidRatioToAddAsLiquidity(amountA, amountB);
            }
        } else {
            (, , lpMinted) = MOE_ROUTER.addLiquidity(
                tokenA,
                tokenB,
                amountA,
                amountB,
                (amountA * STANDARD_SLIPPAGE) / MAX_BPS,
                (amountB * STANDARD_SLIPPAGE) / MAX_BPS,
                address(this),
                block.timestamp
            );
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
