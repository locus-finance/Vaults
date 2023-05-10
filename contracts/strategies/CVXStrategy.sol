// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.12;

import {BaseStrategy, StrategyParams, VaultAPI} from "@yearn-protocol/contracts/BaseStrategy.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

import "hardhat/console.sol";

import {Utils} from "../utils/Utils.sol";
import "../integrations/balancer/IBalancerPriceOracle.sol";
import "../integrations/curve/ICurve.sol";
import "../integrations/convex/IConvexRewards.sol";
import "../integrations/convex/IConvexDeposit.sol";

contract CVXStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    address internal constant USDC_ETH_UNI_V3_POOL =
        0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address internal constant CRV_USDC_UNI_V3_POOL =
        0x9445bd19767F73DCaE6f2De90e6cd31192F62589;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    address internal constant CURVE_SWAP_ROUTER =
        0x99a58482BD75cbab83b27EC03CA68fF489b5788f;
    address internal constant CURVE_CVX_ETH_POOL =
        0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4;
    address internal constant CURVE_CVX_ETH_LP =
        0x3A283D9c08E8b55966afb64C515f5143cf907611;
    address internal constant ETH_CVX_CONVEX_DEPOSIT =
        0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address internal constant ETH_CVX_CONVEX_CRV_REWARDS =
        0xb1Fb0BA0676A1fFA83882c7F4805408bA232C1fA;
    address internal constant CONVEX_CVX_REWARD_POOL =
        0x834B9147Fd23bF131644aBC6e557Daf99C5cDa15;

    uint32 internal constant TWAP_RANGE_SECS = 1800;
    uint256 public slippage = 9500; // 5%

    constructor(address _vault) BaseStrategy(_vault) {
        want.approve(CURVE_SWAP_ROUTER, type(uint256).max);
        ERC20(CURVE_CVX_ETH_LP).approve(
            ETH_CVX_CONVEX_DEPOSIT,
            type(uint256).max
        );
    }

    function setSlippage(uint256 _slippage) external onlyStrategist {
        require(_slippage < 10_000, "!_slippage");
        slippage = _slippage;
    }

    function name() external pure override returns (string memory) {
        return "StrategyCVX";
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfCurveLPStaked() public view returns (uint256) {
        return
            IConvexRewards(ETH_CVX_CONVEX_CRV_REWARDS).balanceOf(address(this));
    }

    function balanceOfCrvRewards() public view returns (uint256) {
        return IConvexRewards(ETH_CVX_CONVEX_CRV_REWARDS).earned(address(this));
    }

    function balanceOfCvxRewards() public view returns (uint256) {
        return IConvexRewards(CONVEX_CVX_REWARD_POOL).earned(address(this));
    }

    function curveLPToWant(uint256 _lpTokens) public view returns (uint256) {
        uint256 ethAmount = ICurve(CURVE_CVX_ETH_POOL).calc_withdraw_one_coin(
            _lpTokens,
            0
        );
        return ethToWant(ethAmount);
    }

    function _withdrawSome(uint256 _amountNeeded) internal {}

    function _exitPosition(uint256) internal {}

    function ethToWant(
        uint256 _amtInWei
    ) public view override returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            USDC_ETH_UNI_V3_POOL,
            TWAP_RANGE_SECS
        );
        return
            OracleLibrary.getQuoteAtTick(
                meanTick,
                uint128(_amtInWei),
                WETH,
                address(want)
            );
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

    function cvxToWant(uint256 crvTokens) public view returns (uint256) {
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

    function estimatedTotalAssets()
        public
        view
        override
        returns (uint256 _wants)
    {
        _wants = balanceOfWant();
        // _wants += curveLPToWant(balanceOfCurveLPStaked());
        // _wants += crvToWant(balanceOfCrvRewards());
        // _wants += cvxToWant(balanceOfCvxRewards());
    }

    function prepareReturn(
        uint256 _debtOutstanding
    )
        internal
        override
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    {
        uint256 _totalAssets = estimatedTotalAssets();
        uint256 _totalDebt = vault.strategies(address(this)).totalDebt;

        if (_totalAssets >= _totalDebt) {
            _profit = _totalAssets - _totalDebt;
            _loss = 0;
        } else {
            _profit = 0;
            _loss = _totalDebt - _totalAssets;
        }

        _withdrawSome(_debtOutstanding + _profit);

        uint256 _liquidWant = want.balanceOf(address(this));

        // enough to pay profit (partial or full) only
        if (_liquidWant <= _profit) {
            _profit = _liquidWant;
            _debtPayment = 0;
            // enough to pay for all profit and _debtOutstanding (partial or full)
        } else {
            _debtPayment = Math.min(_liquidWant - _profit, _debtOutstanding);
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 _wantBal = balanceOfWant();

        if (_wantBal > _debtOutstanding) {
            uint256 _excessWant = _wantBal - _debtOutstanding;

            console.log("Trying to do something with %s want", _excessWant);

            uint256 ethBefore = address(this).balance;
            address[9] memory _route = [
                address(want),
                0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7, // 3pool
                0xdAC17F958D2ee523a2206206994597C13D831ec7, // USDT
                0xD51a44d3FaE010294C616388b506AcdA1bfAAE46, // tricrypto2 pool
                0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, // ETH
                address(0),
                address(0),
                address(0),
                address(0)
            ];
            uint256[3][4] memory _swap_params = [
                [uint256(1), uint256(2), uint256(1)], // USDC -> USDT, stable swap exchange
                [uint256(0), uint256(2), uint256(3)], // USDT -> ETH, cryptoswap exchange
                [uint256(0), uint256(0), uint256(0)],
                [uint256(0), uint256(0), uint256(0)]
            ];
            address[4] memory _pools = [
                address(0),
                address(0),
                address(0),
                address(0)
            ];
            ICurveSwapRouter(CURVE_SWAP_ROUTER).exchange_multiple(
                _route,
                _swap_params,
                _excessWant,
                uint256(0),
                _pools
            );
            console.log("Got %s ETH", address(this).balance - ethBefore);

            uint256[2] memory amounts = [address(this).balance, uint256(0)];
            uint256 lpTokens = ICurve(CURVE_CVX_ETH_POOL).add_liquidity{
                value: address(this).balance
            }(amounts, uint256(0), true);
            console.log("Got %s LP tokens from Curve", lpTokens);

            require(
                IConvexDeposit(ETH_CVX_CONVEX_DEPOSIT).depositAll(
                    uint256(64),
                    true
                ),
                "Convex staking failed"
            );
            console.log("Staked Curve LP: %s", balanceOfCurveLPStaked());
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        return want.balanceOf(address(this));
    }

    function liquidatePosition(
        uint256 _amountNeeded
    ) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {
        uint256 _wantBal = want.balanceOf(address(this));
        if (_wantBal >= _amountNeeded) {
            return (_amountNeeded, 0);
        }

        _withdrawSome(_amountNeeded - _wantBal);
        _wantBal = want.balanceOf(address(this));

        if (_amountNeeded > _wantBal) {
            _liquidatedAmount = _wantBal;
            _loss = _amountNeeded - _wantBal;
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function prepareMigration(address _newStrategy) internal override {}

    function protectedTokens()
        internal
        pure
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](2);
        return protected;
    }

    receive() external payable {}
}
