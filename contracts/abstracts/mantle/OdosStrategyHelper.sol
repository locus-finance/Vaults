// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/ILocusDataFeed.sol";
import "../../interfaces/ILocusDataFeedUser.sol";

abstract contract OdosStrategyHelper is ILocusDataFeedUser {
    using SafeERC20 for IERC20;

    struct RequestOnCalldataCalculation {
        address tokenIn;
        address tokenOut;
        address amountIn;
    }

    address public constant ODOS_ROUTER = 0xD9F4e85489aDCD0bAF0Cd63b4231c6af58c26745;
    ILocusDataFeed private constant LOCUS_DATA_FEED = ILocusDataFeed(0x5662AaAc9fdc97910E648e54076Be71D60D4045f);
    
    /// @dev ODOS_TOPICS_AMOUNT = uint256(type(MoeMerchantStrategyHelper.ReservedTopics).max) + 1
    uint256 public constant ODOS_TOPICS_AMOUNT = 5;

    function updateFeedRequested(
        uint256 topicNumber
    ) public virtual override returns (bytes32) {
        if (msg.sender != address(LOCUS_DATA_FEED)) {
            revert OnlyLocusDataFeed();
        }
        return _updateOdosTopic(topicNumber);
    }

    function _updateOdosTopic(uint256 topicNumber) internal view returns (bytes32) {

    }

    function getRequestsOnCalldataCalculation() external view returns (RequestOnCalldataCalculation[] memory) {

    }

    function _odosSwap(address tokenIn, address tokenOut, uint256 amountIn) internal {
        // consume calldata from topic
        // relay to ODOS Router the call
    }
}