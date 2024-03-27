// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {BaseStrategy, StrategyParams, VaultAPI} from "@yearn-protocol/contracts/BaseStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPenpieStaking} from "../integrations/penpie/IPenpieStaking.sol";
import {IPtPriceOracle} from "../integrations/pendle/IPtPriceOracle.sol";
import {ISyContract} from "../integrations/pendle/ISyContract.sol";
import {IMarket} from "../integrations/pendle/IMarket.sol";
import {IYtToken} from "../integrations/pendle/IYtToken.sol";
import {IPendleRouter} from "../integrations/pendle/IPendleRouter.sol";
import {IPenpieMaster} from "../integrations/penpie/IPenpieMaster.sol";


contract PendleGeneral is BaseStrategy, Initializable {
    using SafeERC20 for IERC20;

    error PendleStrategy__E1();

    address constant public WETH = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address constant public PENDLE = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address constant public ARB = 0x2626664c2603336E57B271c5C0b26F421741e481;


    string private _strategyName;
    IYtToken public ytToken;
    ISyContract public syToken;
    IPtPriceOracle public ptOracle;
    address public lpToken;
    address public underlyingAsset;
    address public poolUnderlyingToWeth;
    address public poolArbToWeth;
    address public poolPendleToWeth;
    
    IPenpieStaking public penpieStaking;
    IPenpieMaster public penpieMaster;

    IMarket public market;
    IPendleRouter public pendleRouter;

    uint256 public slippage = 9000;
    uint256 internal constant BASE_SLIPPAGE = 10000;
    uint256 internal constant USDbC_PROTOCOL_FEE = 100;
    address internal constant UNISWAP_V3_ROUTER =
        0x2626664c2603336E57B271c5C0b26F421741e481;

    uint32 internal constant TWAP_RANGE_SECS = 1800;


    function ethToWant(
        uint256 ethAmount
    ) public view override returns (uint256) {
        return 1;
    }

    constructor(address _vault) BaseStrategy(_vault) {}

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

        uint256 _liquidWant = want.balanceOf(address(this));
        uint256 _amountNeeded = _debtOutstanding + _profit;
        if (_liquidWant <= _amountNeeded) {
            _withdrawSome(_amountNeeded - _liquidWant);
            _liquidWant = want.balanceOf(address(this));
        }

        if (_liquidWant <= _profit) {
            // enough to pay profit (partial or full) only
            _profit = _liquidWant;
            _debtPayment = 0;
        } else {
            // enough to pay for all profit and _debtOutstanding (partial or full)
            _debtPayment = Math.min(_liquidWant - _profit, _debtOutstanding);
        }
    }

    function protectedTokens()
        internal
        pure
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](3);
        protected[0] = ARB;
        protected[1] = PENDLE;
        protected[2] = WETH;
        return protected;
    }

    function initialize(
        address _vault,
        address _strategist,
        string calldata _stratName
    ) public initializer {
        _initialize(_vault, _strategist, _strategist, _strategist);
        _strategyName = _stratName;
    }

    function name() external view override returns (string memory) {
        return string(abi.encodePacked("Pendle strategy - ", _strategyName));
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(vault.token()).balanceOf(address(this));
    }

    function _ytBalance() internal view returns(uint256){
        return IERC20(address(ytToken)).balanceOf(address(this));
    }

    function _lpBalanceStaked() internal view returns(uint256 stakedAmount){
        (stakedAmount,) = penpieMaster.stakingInfo(lpToken, address(this));
    }

    function _ytToWant(uint256 ytAmount) internal view returns(uint256){
        return (ytAmount * _assetToWantRate(10 ** IERC20Metadata(underlyingAsset).decimals()) * 10 ^ 18 / syToken.exchangeRate() - ptOracle.getPtToAssetRate(address(market), TWAP_RANGE_SECS)/10**18);
    }

    function _lpToWant(uint256 lpAmount) internal view returns(uint256){
        _assetToWantRate(ptOracle.getLpToAssetRate(address(market), TWAP_RANGE_SECS) * lpAmount);
    }

    function smthToSmth(
        address pool,
        address tokenFrom,
        address tokenTo,
        uint256 amount
    ) internal view returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(pool, TWAP_RANGE_SECS);
        return
            OracleLibrary.getQuoteAtTick(
                meanTick,
                uint128(amount),
                tokenFrom,
                tokenTo
            );
    }

    function _assetToWantRate(uint256 assetAmount) internal view  returns (uint256) {
        smthToSmth(poolUnderlyingToWeth, underlyingAsset, WETH, assetAmount);
    }

    function _wantToAssetRate(uint256 wantAmount) internal view  returns (uint256) {
        smthToSmth(poolUnderlyingToWeth, WETH, underlyingAsset, wantAmount);
    }

    function _wantToLpYtProportion(uint256 wantAmount) internal returns(uint256 lp, uint256 yt){
        uint256 targetSy = _wantToAssetRate(wantAmount);
        IMarket.MarketState memory state = market.readState();
        uint256 exchRate = ytToken.pyIndexCurrent();
        uint256 totalSyRedeemable = uint256(state.totalSy) + uint256(state.totalPt) / exchRate;
        lp = targetSy * uint256(state.totalLp) / totalSyRedeemable;
        uint256 amountSyFromPy = targetSy - uint256(state.totalSy) * lp / uint256(state.totalLp);
        yt = amountSyFromPy * exchRate;
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return _lpToWant(_lpBalanceStaked()) + _ytToWant(_ytBalance()) + getRewardsInWantToken();
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }
        _claimAndSellRewards();
        uint256 unstakedBalance = balanceOfWant();

        uint256 excessWant;
        if (unstakedBalance > _debtOutstanding) {
            excessWant = unstakedBalance - _debtOutstanding;
        }
        if (excessWant > 0) {
            IPendleRouter.SwapData memory swapData = IPendleRouter.SwapData(IPendleRouter.SwapType.NONE,address(0), "", false);
            IPendleRouter.TokenInput memory inputData = IPendleRouter.TokenInput(WETH, excessWant, WETH, address(0), swapData);
            (uint256 lpOut, uint256 ytOut, , ) = pendleRouter.addLiquiditySingleTokenKeepYt(address(this), address(market), 0, 0, inputData);
            (uint256 lpExpected, uint256 ytExpected) = _wantToLpYtProportion(excessWant);
            if (lpExpected * slippage / BASE_SLIPPAGE < lpOut) revert  PendleStrategy__E1();
            if (ytExpected * slippage / BASE_SLIPPAGE < ytOut) revert  PendleStrategy__E1();
            penpieStaking.depositMarket(address(market), lpOut);
        }

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

    function liquidateAllPositions()
        internal
        override
        returns (uint256 _amountFreed)
    {
        _claimAndSellRewards();
        _exitPosition(_lpToWant(_lpBalanceStaked()) + _ytToWant(_ytBalance()));
        return want.balanceOf(address(this));
    }

    function prepareMigration(address _newStrategy) internal override {
        uint256 assets = liquidateAllPositions();
        want.safeTransfer(_newStrategy, assets);
    }

    function getRewardsInWantToken() public view returns (uint256 amount) {
        (, address[] memory bonusRewardTokens, , uint256[] memory bonusTokensAmounts) = penpieMaster.allPendingTokens(lpToken, address(this));
        uint256 len = bonusRewardTokens.length;
        for (uint256 i; i < len; i++) {
            if (bonusRewardTokens[i] == ARB) {
                amount += smthToSmth(poolArbToWeth, ARB, WETH, bonusTokensAmounts[i]);
            } else if(bonusRewardTokens[i] == PENDLE){
                amount += smthToSmth(poolPendleToWeth, PENDLE, WETH, bonusTokensAmounts[i]);
            }
        }
    }

    function _withdrawSome(uint256 _amountNeeded) internal {
        if (_amountNeeded == 0) {
            return;
        }
        uint256 rewards = getRewardsInWantToken();
        if (rewards >= _amountNeeded) {
            _claimAndSellRewards();
        } else {
            uint256 _wantToUnstake = Math.min(
                _lpToWant(_lpBalanceStaked()),
                _amountNeeded - rewards
            );
            _exitPosition(_wantToUnstake);
        }
    }

    function _claimAndSellRewards() internal {
        address[] memory stakingTokens = new address[](1);
        (, address[] memory bonusRewardTokens, , ) = penpieMaster.allPendingTokens(lpToken, address(this));
        penpieMaster.multiclaimSpecPNP(stakingTokens, bonusRewardTokens ,false);
        _sellPendleForWant(IERC20(PENDLE).balanceOf(address(this)));
        _sellArbForWant(IERC20(ARB).balanceOf(address(this)));

    }

    function _sellPendleForWant(uint256 amount) internal {
        ISwapRouter.ExactInputSingleParams memory params;
        params.tokenIn = PENDLE;
        params.tokenOut = WETH;
        params.fee = 3000;
        params.recipient = address(this);
        params.deadline = block.timestamp;
        params.amountIn = amount;
        params.amountOutMinimum = smthToSmth(poolPendleToWeth, PENDLE, WETH, amount) * slippage / 10000;
        params.sqrtPriceLimitX96 = 0;
        ISwapRouter(UNISWAP_V3_ROUTER).exactInputSingle(params);
    }

    function _sellArbForWant(uint256 amount) internal {
        ISwapRouter.ExactInputSingleParams memory params;
        params.tokenIn = ARB;
        params.tokenOut = WETH;
        params.fee = 500;
        params.recipient = address(this);
        params.deadline = block.timestamp;
        params.amountIn = amount;
        params.amountOutMinimum = smthToSmth(poolArbToWeth, ARB, WETH, amount) * slippage / 10000;
        params.sqrtPriceLimitX96 = 0;
        ISwapRouter(UNISWAP_V3_ROUTER).exactInputSingle(params);
    }

    function _exitPosition(uint256 _stakedAmountInWant) internal {
        _claimAndSellRewards();
        (uint256 lpAmount, uint256 ytAmount) = _wantToLpYtProportion(_stakedAmountInWant);
        if (lpAmount > _lpBalanceStaked()) {
            lpAmount = _lpBalanceStaked();
        }
        if (ytAmount > _ytBalance() ) {
            ytAmount = _ytBalance();
        }
        //Todo
    }
}
