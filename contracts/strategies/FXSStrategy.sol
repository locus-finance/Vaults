// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {BaseStrategy, StrategyParams, VaultAPI} from "@yearn-protocol/contracts/BaseStrategy.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

import "../integrations/balancer/IBalancerPriceOracle.sol";
import "../integrations/curve/ICurve.sol";
import "../integrations/convex/IConvexRewards.sol";
import "../integrations/convex/IConvexDeposit.sol";
import "../integrations/uniswap/v3/IV3SwapRouter.sol";

import "../utils/Utils.sol";
import "../utils/CVXRewards.sol";

contract FXSStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    address internal constant USDC_ETH_UNI_V3_POOL =
        0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address internal constant CRV_USDC_UNI_V3_POOL =
        0x9445bd19767F73DCaE6f2De90e6cd31192F62589;
    address internal constant CVX_USDC_UNI_V3_POOL =
        0x575e96f61656b275CA1e0a67d9B68387ABC1d09C;
    address internal constant CVX_CRV_UNI_V3_POOL =
        0x645c3A387b8633dF1D4D71CA4b50D27233Bcb887;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address internal constant FXS = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
    address internal constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

    address internal constant CURVE_SWAP_ROUTER =
        0x99a58482BD75cbab83b27EC03CA68fF489b5788f;
    address internal constant CONVEX_CVX_REWARD_POOL =
        0xE2585F27bf5aaB7756f626D6444eD5Fc9154e606;
    address internal constant CONVEX_FXS_REWARD_POOL =
        0x28120D9D49dBAeb5E34D6B809b842684C482EF27;

    address internal constant FXS_FRAX_UNI_V3_POOL =
        0xb64508B9f7b81407549e13DB970DD5BB5C19107F;
    uint24 internal constant FXS_FRAX_UNI_V3_FEE = 10000;

    address internal constant FRAX_USDC_UNI_V3_POOL =
        0xc63B0708E2F7e69CB8A1df0e1389A98C35A76D52;
    uint24 internal constant FRAX_USDC_UNI_V3_FEE = 500;

    address internal constant CURVE_FXS_POOL =
        0xd658A338613198204DCa1143Ac3F01A722b5d94A;
    address internal constant CURVE_FXS_LP =
        0xF3A43307DcAFa93275993862Aae628fCB50dC768;

    address internal constant FXS_CONVEX_DEPOSIT =
        0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address internal constant FXS_CONVEX_CRV_REWARDS =
        0xf27AFAD0142393e4b3E5510aBc5fe3743Ad669Cb;

    address internal constant UNISWAP_V3_ROUTER =
        0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    uint32 internal constant TWAP_RANGE_SECS = 1800;
    uint256 public slippage = 9300; // 7%

    constructor(address _vault) BaseStrategy(_vault) {
        ERC20(CRV).approve(CURVE_SWAP_ROUTER, type(uint256).max);
        ERC20(CVX).approve(CURVE_SWAP_ROUTER, type(uint256).max);
        ERC20(CURVE_FXS_LP).approve(FXS_CONVEX_DEPOSIT, type(uint256).max);
        ERC20(CURVE_FXS_LP).approve(CURVE_FXS_POOL, type(uint256).max);
        ERC20(FXS).approve(CURVE_FXS_POOL, type(uint256).max);
        ERC20(FXS).approve(UNISWAP_V3_ROUTER, type(uint256).max);

        want.approve(UNISWAP_V3_ROUTER, type(uint256).max);
    }

    function setSlippage(uint256 _slippage) external onlyStrategist {
        require(_slippage < 10_000, "!_slippage");
        slippage = _slippage;
    }

    function name() external pure override returns (string memory) {
        return "StrategyFXS";
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfCurveLPUnstaked() public view returns (uint256) {
        return ERC20(CURVE_FXS_LP).balanceOf(address(this));
    }

    function balanceOfCurveLPStaked() public view returns (uint256) {
        return IConvexRewards(FXS_CONVEX_CRV_REWARDS).balanceOf(address(this));
    }

    function balanceOfCrvRewards() public view virtual returns (uint256) {
        return
            ERC20(CRV).balanceOf(address(this)) +
            IConvexRewards(FXS_CONVEX_CRV_REWARDS).earned(address(this));
    }

    function balanceOfFxsRewards() public view returns (uint256) {
        return
            ERC20(FXS).balanceOf(address(this)) +
            IConvexRewards(CONVEX_FXS_REWARD_POOL).earned(address(this));
    }

    function balanceOfCvxRewards() public view virtual returns (uint256) {
        uint256 crvRewards = IConvexRewards(FXS_CONVEX_CRV_REWARDS).earned(
            address(this)
        );

        return
            ERC20(CVX).balanceOf(address(this)) +
            IConvexRewards(CONVEX_CVX_REWARD_POOL).earned(address(this)) +
            CVXRewardsMath.convertCrvToCvx(crvRewards);
    }

    function curveLPToWant(uint256 _lpTokens) public view returns (uint256) {
        uint256 fxsAmount = (
            _lpTokens > 0
                ? (ICurve(CURVE_FXS_POOL).lp_price() * _lpTokens) / 1e18
                : 0
        );
        return fxsToWant(fxsAmount);
    }

    function wantToCurveLP(
        uint256 _want
    ) public view virtual returns (uint256) {
        uint256 oneCurveLPPrice = curveLPToWant(1e18);
        return (_want * 1e18) / oneCurveLPPrice;
    }

    function _withdrawSome(uint256 _amountNeeded) internal {
        if (_amountNeeded == 0) {
            return;
        }
        uint256 lpTokensToWithdraw = Math.min(
            wantToCurveLP(_amountNeeded),
            balanceOfCurveLPStaked()
        );
        _exitPosition(lpTokensToWithdraw);
    }

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

    function fraxToWant(uint256 fraxTokens) public view returns (uint256) {
        return
            Utils.scaleDecimals(fraxTokens, ERC20(FRAX), ERC20(address(want)));
    }

    function fxsToWant(uint256 fxsTokens) public view returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            FXS_FRAX_UNI_V3_POOL,
            TWAP_RANGE_SECS
        );
        return
            fraxToWant(
                OracleLibrary.getQuoteAtTick(
                    meanTick,
                    uint128(fxsTokens),
                    FXS,
                    FRAX
                )
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

    function cvxToWant(uint256 cvxTokens) public view returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            CVX_USDC_UNI_V3_POOL,
            TWAP_RANGE_SECS
        );
        return
            OracleLibrary.getQuoteAtTick(
                meanTick,
                uint128(cvxTokens),
                CVX,
                address(want)
            );
    }

    function cvxToCrv(uint256 cvxTokens) public view returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            CVX_CRV_UNI_V3_POOL,
            TWAP_RANGE_SECS
        );
        return
            OracleLibrary.getQuoteAtTick(
                meanTick,
                uint128(cvxTokens),
                CVX,
                CRV
            );
    }

    function estimatedTotalAssets()
        public
        view
        virtual
        override
        returns (uint256 _wants)
    {
        _wants = balanceOfWant();
        _wants += curveLPToWant(
            balanceOfCurveLPStaked() + balanceOfCurveLPUnstaked()
        );
        _wants += crvToWant(balanceOfCrvRewards());
        _wants += cvxToWant(balanceOfCvxRewards());
        _wants += fxsToWant(balanceOfFxsRewards());
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
        IConvexRewards(FXS_CONVEX_CRV_REWARDS).getReward(address(this), true);
        _sellCrvAndCvx(
            ERC20(CRV).balanceOf(address(this)),
            ERC20(CVX).balanceOf(address(this))
        );

        uint256 _wantBal = balanceOfWant();

        if (_wantBal > _debtOutstanding) {
            uint256 _excessWant = _wantBal - _debtOutstanding;

            uint256 fxsExpectedUnscaled = (_excessWant *
                (10 ** ERC20(address(want)).decimals())) / fxsToWant(1 ether);
            uint256 fxsExpectedScaled = Utils.scaleDecimals(
                fxsExpectedUnscaled,
                ERC20(address(want)),
                ERC20(FXS)
            );

            IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter
                .ExactInputParams({
                    path: abi.encodePacked(
                        address(want),
                        FRAX_USDC_UNI_V3_FEE,
                        FRAX,
                        FXS_FRAX_UNI_V3_FEE,
                        FXS
                    ),
                    recipient: address(this),
                    amountIn: _excessWant,
                    amountOutMinimum: (fxsExpectedScaled * slippage) / 10000
                });
            IV3SwapRouter(UNISWAP_V3_ROUTER).exactInput(params);
        }

        uint256 fxsBalance = ERC20(FXS).balanceOf(address(this));
        if (fxsBalance > 0) {
            uint256 lpExpected = (fxsBalance * 1e18) /
                ICurve(CURVE_FXS_POOL).lp_price();
            uint256[2] memory amounts = [fxsBalance, uint256(0)];
            ICurve(CURVE_FXS_POOL).add_liquidity(
                amounts,
                (lpExpected * slippage) / 10000,
                false
            );
        }

        if (balanceOfCurveLPUnstaked() > 0) {
            require(
                IConvexDeposit(FXS_CONVEX_DEPOSIT).depositAll(
                    uint256(72),
                    true
                ),
                "Convex staking failed"
            );
        }
    }

    function _sellCrvAndCvx(uint256 _crvAmount, uint256 _cvxAmount) internal {
        if (_cvxAmount > 0) {
            address[9] memory _route = [
                CVX, // CVX
                0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4, // cvxeth pool
                0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, // ETH
                0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511, // crveth pool
                CRV, // CRV
                address(0),
                address(0),
                address(0),
                address(0)
            ];
            uint256[3][4] memory _swap_params = [
                [uint256(1), uint256(0), uint256(3)], // CVX -> ETH, cryptoswap exchange
                [uint256(0), uint256(1), uint256(3)], // ETH -> CRV, cryptoswap exchange
                [uint256(0), uint256(0), uint256(0)],
                [uint256(0), uint256(0), uint256(0)]
            ];
            uint256 _expected = (cvxToCrv(_cvxAmount) * slippage) / 10000;
            address[4] memory _pools = [
                address(0),
                address(0),
                address(0),
                address(0)
            ];

            _crvAmount += ICurveSwapRouter(CURVE_SWAP_ROUTER).exchange_multiple(
                _route,
                _swap_params,
                _cvxAmount,
                _expected,
                _pools
            );
        }

        if (_crvAmount > 0) {
            address[9] memory _route = [
                CRV, // CRV
                0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511, // crveth pool
                0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, // ETH
                0xD51a44d3FaE010294C616388b506AcdA1bfAAE46, // tricrypto2 pool
                0xdAC17F958D2ee523a2206206994597C13D831ec7, // USDT
                0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7, // 3pool
                address(want), // USDC
                address(0),
                address(0)
            ];
            uint256[3][4] memory _swap_params = [
                [uint256(1), uint256(0), uint256(3)], // CRV -> ETH, cryptoswap exchange
                [uint256(2), uint256(0), uint256(3)], // ETH -> USDT, cryptoswap exchange
                [uint256(2), uint256(1), uint256(1)], // USDT -> USDC, stable swap exchange
                [uint256(0), uint256(0), uint256(0)]
            ];
            uint256 _expected = (crvToWant(_crvAmount) * slippage) / 10000;
            address[4] memory _pools = [
                address(0),
                address(0),
                address(0),
                address(0)
            ];

            ICurveSwapRouter(CURVE_SWAP_ROUTER).exchange_multiple(
                _route,
                _swap_params,
                _crvAmount,
                _expected,
                _pools
            );
        }
    }

    function _exitPosition(uint256 _stakedLpTokens) internal {
        IConvexRewards(FXS_CONVEX_CRV_REWARDS).withdrawAndUnwrap(
            _stakedLpTokens,
            true
        );

        _sellCrvAndCvx(
            ERC20(CRV).balanceOf(address(this)),
            ERC20(CVX).balanceOf(address(this))
        );

        uint256 lpTokens = balanceOfCurveLPUnstaked();
        uint256 withdrawAmount = ICurve(CURVE_FXS_POOL).calc_withdraw_one_coin(
            lpTokens,
            0
        );
        ICurve(CURVE_FXS_POOL).remove_liquidity_one_coin(
            lpTokens,
            0,
            (withdrawAmount * slippage) / 10000,
            true
        );

        _sellFxs(ERC20(FXS).balanceOf(address(this)));
    }

    function _sellFxs(uint256 fxsAmount) internal {
        if (fxsAmount > 0) {
            IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter
                .ExactInputParams({
                    path: abi.encodePacked(
                        FXS,
                        FXS_FRAX_UNI_V3_FEE,
                        FRAX,
                        FRAX_USDC_UNI_V3_FEE,
                        address(want)
                    ),
                    recipient: address(this),
                    amountIn: fxsAmount,
                    amountOutMinimum: (fxsToWant(fxsAmount) * slippage) / 10000
                });
            IV3SwapRouter(UNISWAP_V3_ROUTER).exactInput(params);
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        _exitPosition(balanceOfCurveLPStaked());
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

    function prepareMigration(address _newStrategy) internal override {
        IConvexRewards(FXS_CONVEX_CRV_REWARDS).withdrawAndUnwrap(
            balanceOfCurveLPStaked(),
            true
        );
        IERC20(CRV).safeTransfer(
            _newStrategy,
            IERC20(CRV).balanceOf(address(this))
        );
        IERC20(CVX).safeTransfer(
            _newStrategy,
            IERC20(CVX).balanceOf(address(this))
        );
        IERC20(CURVE_FXS_LP).safeTransfer(
            _newStrategy,
            IERC20(CURVE_FXS_LP).balanceOf(address(this))
        );
    }

    function protectedTokens()
        internal
        pure
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](4);
        protected[0] = CVX;
        protected[1] = CRV;
        protected[2] = FXS;
        protected[3] = CURVE_FXS_LP;
        return protected;
    }
}
