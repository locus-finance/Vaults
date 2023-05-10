// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.12;

import {YCRVStrategy, ERC20} from "../strategies/YCRVStrategy.sol";

contract MockYCRVStrategy is YCRVStrategy {
    bool internal _isTotalAssetsOverridden;
    uint256 internal _estimatedTotalAssets;

    bool internal _isWantToStYCRVOverriden;
    uint256 internal _wantToStYCRV;

    constructor(address vault) YCRVStrategy(vault) {}

    function overrideEstimatedTotalAssets(uint256 targetValue) external {
        _isTotalAssetsOverridden = true;
        _estimatedTotalAssets = targetValue;
    }

    function overrideWantToStYCRV(uint256 targetValue) external {
        _isWantToStYCRVOverriden = true;
        _wantToStYCRV = targetValue;
    }

    function wantToStYCrv(
        uint256 value
    ) public view override returns (uint256) {
        if (_isWantToStYCRVOverriden) {
            return _wantToStYCRV;
        }
        return super.wantToStYCrv(value);
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

    function scaleDecimals(
        uint _amount,
        ERC20 _fromToken,
        ERC20 _toToken
    ) public view returns (uint _scaled) {
        return _scaleDecimals(_amount, _fromToken, _toToken);
    }
}
