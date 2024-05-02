// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../integrations/merchantMoe/IMoePair.sol";
import "../../integrations/merchantMoe/IMoeFactory.sol";
import "../../integrations/merchantMoe/IMoeRouter.sol";
import "../../interfaces/ILocusDataFeed.sol";
import "../../interfaces/ILocusDataFeedUser.sol";

abstract contract MoeMerchantStrategyHelper is ILocusDataFeedUser {
    using SafeERC20 for IERC20;

    enum ReservedTopics {
        TOKEN_A,
        TOKEN_B,
        RESERVE_A,
        RESERVE_B
    }

    struct RemoveLiquidityData {
        uint256 amountAWithdrawn;
        uint256 amountBWithdrawn;
    }

    IMoeRouter public constant MOE_ROUTER =
        IMoeRouter(0xeaEE7EE68874218c3558b40063c42B82D3E7232a);
    IMoeFactory public constant MOE_FACTORY =
        IMoeFactory(0x5bEf015CA9424A7C07B68490616a4C1F094BEdEc);
    
    uint256 public constant STANDARD_SLIPPAGE = 9000;
    uint256 public constant MAX_BPS = 10000;

    ILocusDataFeed private constant LOCUS_DATA_FEED = ILocusDataFeed(0x5662AaAc9fdc97910E648e54076Be71D60D4045f);

    function updateFeedRequested(
        uint256 topicNumber
    ) public virtual override returns (bytes32) {
        if (msg.sender != address(LOCUS_DATA_FEED)) {
            revert OnlyLocusDataFeed();
        }
        return _updateMoeTopic(topicNumber);
    }

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

    function _moeMerchantAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA
    ) internal returns (uint256 lpMinted) {
        uint256 reserve0 = LOCUS_DATA_FEED.parseUint256FromFeed(
            address(this),
            uint256(ReservedTopics.RESERVE_A)
        );
        uint256 reserve1 = LOCUS_DATA_FEED.parseUint256FromFeed(
            address(this),
            uint256(ReservedTopics.RESERVE_B)
        );

        uint256 tokensAToAdd = amountA / 2;
        uint256 tokensBToAdd = MOE_ROUTER.quote(tokensAToAdd, reserve0, reserve1);
        uint256 tokensBToAddWithSlippage = (tokensBToAdd * STANDARD_SLIPPAGE) / MAX_BPS; 
        uint256 swappedTokensB = _moeMerchantSwap(tokenA, tokenB, tokensAToAdd, tokensBToAddWithSlippage);

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

    function _updateMoeTopic(uint256 topicNumber) internal view returns (bytes32 result) {
        IMoePair pair = IMoePair(
            MOE_FACTORY.getPair(
                LOCUS_DATA_FEED.parseAddressFromFeed(
                    address(this),
                    uint256(ReservedTopics.TOKEN_A)
                ),
                LOCUS_DATA_FEED.parseAddressFromFeed(
                    address(this),
                    uint256(ReservedTopics.TOKEN_B)
                )
            )
        );
        if (topicNumber == uint256(ReservedTopics.RESERVE_A)) {
            (uint112 reserve0, , ) = pair.getReserves();
            result = bytes32(uint256(reserve0));
        } else if (topicNumber == uint256(ReservedTopics.RESERVE_B)) {
            (, uint112 reserve1, ) = pair.getReserves();
            result = bytes32(uint256(reserve1));
        } else if (
            topicNumber == uint256(ReservedTopics.TOKEN_A) ||
            topicNumber == uint256(ReservedTopics.TOKEN_B)
        ) {
            result = LOCUS_DATA_FEED.getValue(topicNumber);
        }
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[45] private __gap;
}
