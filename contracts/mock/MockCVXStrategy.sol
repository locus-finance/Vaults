// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {CVXStrategy, ERC20} from "../strategies/CVXStrategy.sol";

contract MockCVXStrategy is CVXStrategy {
    bool internal _isWantToCurveLPOverriden;
    uint256 internal _wantToCurveLP;

    bool internal _isTotalAssetsOverridden;
    uint256 internal _estimatedTotalAssets;

    constructor(address vault) CVXStrategy(vault) {}

    function overrideWantToCurveLP(uint256 target) external {
        _isWantToCurveLPOverriden = true;
        _wantToCurveLP = target;
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

    function wantToCurveLP(
        uint256 _want
    ) public view override returns (uint256) {
        if (_isWantToCurveLPOverriden) return _wantToCurveLP;
        return super.wantToCurveLP(_want);
    }
}
