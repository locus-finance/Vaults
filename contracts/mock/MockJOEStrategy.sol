// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {JOEStrategy, ERC20} from "../strategies/arbitrum/JOEStrategy.sol";

contract MockJOEStrategy is JOEStrategy {
    bool internal _isWantToJoeOverriden;
    uint256 internal _wantToJoe;

    bool internal _isTotalAssetsOverridden;
    uint256 internal _estimatedTotalAssets;

    bool internal _isBalanceOfRewardsOverriden;
    uint256 internal _balanceOfRewards;

    constructor(address vault) JOEStrategy(vault) {}

    function overrideWantToJoe(uint256 target) external {
        _isWantToJoeOverriden = true;
        _wantToJoe = target;
    }

    function overrideBalanceOfRewards(uint256 target) external {
        _isBalanceOfRewardsOverriden = true;
        _balanceOfRewards = target;
    }

    function overrideEstimatedTotalAssets(uint256 targetValue) external {
        _isTotalAssetsOverridden = true;
        _estimatedTotalAssets = targetValue;
    }

    function estimatedTotalAssets()
        public
        view
        override
        returns (uint256 _wants)
    {
        if (_isTotalAssetsOverridden) return _estimatedTotalAssets;
        return super.estimatedTotalAssets();
    }

    function wantToJoe(uint256 _want) public view override returns (uint256) {
        if (_isWantToJoeOverriden) return _wantToJoe;
        return super.wantToJoe(_want);
    }

    function balanceOfRewards() public view override returns (uint256) {
        if (_isBalanceOfRewardsOverriden) return _balanceOfRewards;
        return super.balanceOfRewards();
    }
}
