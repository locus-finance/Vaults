// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {BaseStrategy, StrategyParams} from "../../BaseStrategy.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// import "./interfaces/ "

contract ArbitrumDeFiStrategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;

    bool public claimRewards = true; // claim rewards when withdrawAndUnwrap

    function initialize(address _vault) BaseStrategy(_vault) {  }

    function name() external view override returns (string memory) {
        return "ArbitrumDeFi";
    }

    function _scaleDecimals(uint _amount, ERC20 _fromToken, ERC20 _toToken) internal view returns (uint _scaled) {
        uint decFrom = _fromToken.decimals();
        uint decTo = _toToken.decimals();
        return decTo > decFrom ? _amount.mul(10 ** (decTo.sub(decFrom))) : _amount.div(10 ** (decFrom.sub(decTo)));
    }

    function estimatedTotalAssets() public view override returns (uint256 _wants) {
        return _wants;
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    { }

    function adjustPosition(uint256 _debtOutstanding) internal override { }

    function withdrawSome(uint256 _amountNeeded) internal { }
}