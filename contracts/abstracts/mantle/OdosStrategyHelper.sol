// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/ILocusDataFeed.sol";
import "../../interfaces/ILocusDataFeedUser.sol";

abstract contract OdosStrategyHelper is ILocusDataFeedUser {
    using SafeERC20 for IERC20;

    ILocusDataFeed public constant LOCUS_DATA_FEED = ILocusDataFeed(0x5662AaAc9fdc97910E648e54076Be71D60D4045f);

    function updateFeedRequested(
        uint256 topicNumber
    ) public virtual override returns (bytes32 result) {
        if (msg.sender != address(LOCUS_DATA_FEED)) {
            revert OnlyLocusDataFeed();
        }

    }

    function _odosSwap(address tokenIn, address tokenOut, uint256 amountIn) internal {
        
    }
}