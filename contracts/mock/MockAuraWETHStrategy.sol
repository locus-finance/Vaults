// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {AuraWETHStrategy, ERC20} from "../strategies/AuraWETHStrategy.sol";

contract MockAuraWETHStrategy is AuraWETHStrategy {
    bool internal _isWantToBptOverriden;
    uint256 internal _wantToBpt;

    bool internal _isTotalAssetsOverridden;
    uint256 internal _estimatedTotalAssets;

    constructor(address vault) AuraWETHStrategy(vault) {}

    function overrideWantToBpt(uint256 target) external {
        _isWantToBptOverriden = true;
        _wantToBpt = target;
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

    function wantToBpt(uint256 _want) public view override returns (uint256) {
        if (_isWantToBptOverriden) return _wantToBpt;
        return super.wantToBpt(_want);
    }
}
