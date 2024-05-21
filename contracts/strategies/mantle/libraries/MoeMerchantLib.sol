// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "../../../integrations/merchantMoe/IMoePair.sol";
import "../../../integrations/merchantMoe/IMoeFactory.sol";
import "../../../integrations/merchantMoe/IMoeRouter.sol";

library MoeMerchantLib {
    IMoeRouter public constant MOE_ROUTER =
        IMoeRouter(0xeaEE7EE68874218c3558b40063c42B82D3E7232a);
    IMoeFactory public constant MOE_FACTORY =
        IMoeFactory(0x5bEf015CA9424A7C07B68490616a4C1F094BEdEc);

    uint256 private constant MAX_BPS = 10000;

    function moeMerchantSwap(
        address from,
        address to,
        uint256 amount,
        uint256 slippageBps,
        function(address, uint256, address) internal view returns(uint256) consult
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

    function moeMerchantAddLiquiditySingle(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 slippageBps,
        function(address, uint256, address) internal view returns(uint256) consult
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
        uint256 amountBToAdd = moeMerchantSwap(
            tokenA,
            tokenB,
            amountAToSwapToB,
            slippageBps,
            consult
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

    function moeMerchantAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA, // any amount (even violating the ratio in the reserves)
        uint256 amountB, // any amount (even violating the ratio in the reserves)
        uint256 slippageBps,
        function(address, uint256, address) internal view returns(uint256) consult
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

    function moeMerchantRemoveLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountLp
    ) internal returns (uint256 amountAWithdrawn, uint256 amountBWithdrawn) {
        IMoePair(MOE_FACTORY.getPair(tokenA, tokenB)).approve(
            address(MOE_ROUTER),
            amountLp
        );
        (amountAWithdrawn, amountBWithdrawn) = MOE_ROUTER
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
}