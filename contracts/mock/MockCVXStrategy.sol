// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {CVXStrategy, ERC20} from "../strategies/CVXStrategy.sol";

contract MockCVXStrategy is CVXStrategy {
    bool internal _isBalanceOfCrvRewardsOverriden;
    bool internal _isBalanceOfCvxRewardsOverriden;

    bool internal _isWantToCurveLPOverriden;
    uint256 internal _wantToCurveLP;

    bool internal _isTotalAssetsOverridden;
    uint256 internal _estimatedTotalAssets;

    constructor(address vault) CVXStrategy(vault) {}

    function overrideBalanceOfCrvRewards() external {
        _isBalanceOfCrvRewardsOverriden = true;
    }

    function overrideBalanceOfCvxRewards() external {
        _isBalanceOfCvxRewardsOverriden = true;
    }

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

    function balanceOfCrvRewards() public view override returns (uint256) {
        if (_isBalanceOfCrvRewardsOverriden)
            return ERC20(CRV).balanceOf(address(this));
        return super.balanceOfCrvRewards();
    }

    function balanceOfCvxRewards() public view override returns (uint256) {
        if (_isBalanceOfCvxRewardsOverriden)
            return ERC20(CVX).balanceOf(address(this));
        return super.balanceOfCvxRewards();
    }

    function wantToCurveLP(
        uint256 _want
    ) public view override returns (uint256) {
        if (_isWantToCurveLPOverriden) return _wantToCurveLP;
        return super.wantToCurveLP(_want);
    }
}
