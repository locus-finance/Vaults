// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {AuraBALStrategy, ERC20} from "../strategies/AuraBALStrategy.sol";

contract MockAuraBALStrategy is AuraBALStrategy {
    bool internal _isWantToAuraBalOverriden;
    uint256 internal _wantToAuraBal;

    bool internal _isTotalAssetsOverridden;
    uint256 internal _estimatedTotalAssets;

    constructor(address vault) AuraBALStrategy(vault) {}

    function overrideWantToAuraBal(uint256 target) external {
        _isWantToAuraBalOverriden = true;
        _wantToAuraBal = target;
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

    function wantToAuraBal(
        uint256 _want
    ) public view override returns (uint256) {
        if (_isWantToAuraBalOverriden) return _wantToAuraBal;
        return super.wantToAuraBal(_want);
    }
}
