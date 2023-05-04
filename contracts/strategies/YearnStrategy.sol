// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.12;

import {BaseStrategy, StrategyParams, VaultAPI} from "@yearn-protocol/contracts/BaseStrategy.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

import "../interfaces/IBalancerPriceOracle.sol";
import "../interfaces/ICurve.sol";

contract YearnStrategy is BaseStrategy {
    address internal constant yCRVVault =
        0x27B5739e22ad9033bcBf192059122d163b60349D;
    address internal constant yCRV = 0xFCc5c47bE19d06BF83eB04298b026F81069ff65b;
    address internal constant USDC_WETH_BALANCER_POOL =
        0x96646936b91d6B9D7D0c47C496AfBF3D6ec7B6f8;
    address internal constant YCRV_CRV_CURVE_POOL =
        0x453D92C7d4263201C69aACfaf589Ed14202d83a4;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant CRV_USDC_UNI_V3_POOL =
        0x9445bd19767F73DCaE6f2De90e6cd31192F62589;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint32 internal constant TWAP_RANGE_SECS = 1800;

    constructor(address _vault) BaseStrategy(_vault) {}

    function name() external pure override returns (string memory) {
        return "StrategyYearn";
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfStakedYCrv() public view returns (uint256) {
        return IERC20(yCRVVault).balanceOf(address(this));
    }

    function balanceOfYCrv() public view returns (uint256) {
        return IERC20(yCRV).balanceOf(address(this));
    }

    function crvToWant(uint256 crvTokens) public view returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            CRV_USDC_UNI_V3_POOL,
            TWAP_RANGE_SECS
        );
        return
            OracleLibrary.getQuoteAtTick(
                meanTick,
                uint128(crvTokens),
                CRV,
                address(want)
            );
    }

    function yCrvToWant(uint256 yCRVTokens) public view returns (uint256) {
        uint256 crvRatio = ICurve(YCRV_CRV_CURVE_POOL).get_virtual_price();
        uint256 crvTokens = (yCRVTokens * 1e18) / crvRatio;
        return crvToWant(crvTokens);
    }

    function _scaleDecimals(
        uint _amount,
        ERC20 _fromToken,
        ERC20 _toToken
    ) internal view returns (uint _scaled) {
        uint decFrom = _fromToken.decimals();
        uint decTo = _toToken.decimals();

        if (decTo > decFrom) {
            return _amount * (10 ** (decTo - decFrom));
        } else {
            return _amount / (10 ** (decFrom - decTo));
        }
    }

    function ethToWant(
        uint256 _amtInWei
    ) public view override returns (uint256) {
        IBalancerPriceOracle.OracleAverageQuery[] memory queries;
        queries = new IBalancerPriceOracle.OracleAverageQuery[](1);
        queries[0] = IBalancerPriceOracle.OracleAverageQuery({
            variable: IBalancerPriceOracle.Variable.PAIR_PRICE,
            secs: TWAP_RANGE_SECS,
            ago: 0
        });

        uint256[] memory results;
        results = IBalancerPriceOracle(USDC_WETH_BALANCER_POOL)
            .getTimeWeightedAverage(queries);

        return
            _scaleDecimals(
                (_amtInWei * results[0]) / 1e18,
                ERC20(WETH),
                ERC20(address(want))
            );
    }

    function estimatedTotalAssets()
        public
        view
        override
        returns (uint256 _wants)
    {
        _wants = balanceOfWant();
    }

    function prepareReturn(
        uint256 _debtOutstanding
    )
        internal
        override
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    {}

    function adjustPosition(uint256 _debtOutstanding) internal override {}

    function liquidateAllPositions() internal override returns (uint256) {}

    function liquidatePosition(
        uint256 _amountNeeded
    ) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {}

    function prepareMigration(address _newStrategy) internal override {}

    function protectedTokens()
        internal
        pure
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](0);
        return protected;
    }
}
