// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {GMXStrategy, ERC20} from "../../strategies/arbitrum/GMXStrategy.sol";

contract MockGMXStrategy is GMXStrategy {
    bool internal _isWantToGmxOverriden;
    uint256 internal _wantToGmx;

    bool internal _isTotalAssetsOverridden;
    uint256 internal _estimatedTotalAssets;

    constructor(address vault) GMXStrategy(vault) {}

    function overrideWantToGmx(uint256 target) external {
        _isWantToGmxOverriden = true;
        _wantToGmx = target;
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

    function wantToGmx(uint256 _want) public view override returns (uint256) {
        if (_isWantToGmxOverriden) return _wantToGmx;
        return super.wantToGmx(_want);
    }
}
