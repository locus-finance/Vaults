// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {BaseStrategy, StrategyParams, VaultAPI} from "@yearn-protocol/contracts/BaseStrategy.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

import "../../utils/Utils.sol";
import "../../integrations/gmx/IRewardRouterV2.sol";
import "../../integrations/gmx/IRewardTracker.sol";
import "../../integrations/uniswap/v3/IV3SwapRouter.sol";

contract GMXStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    address internal constant STAKED_GMX_TRACKER =
        0x908C4D94D34924765f1eDc22A1DD098397c59dD4;
    address internal constant FEE_GMX_TRACKER =
        0xd2D1162512F927a7e282Ef43a362659E4F2a728F;

    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address internal constant GMX = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;
    address internal constant ES_GMX =
        0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA;

    address internal constant GMX_REWARD_ROUTER =
        0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;

    address internal constant UNISWAP_V3_ROUTER =
        0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    address internal constant ETH_USDC_UNI_V3_POOL =
        0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443;
    uint24 internal constant ETH_USDC_UNI_V3_FEE = 500;

    address internal constant ETH_GMX_UNI_V3_POOL =
        0x80A9ae39310abf666A87C743d6ebBD0E8C42158E;
    uint24 internal constant ETH_GMX_UNI_V3_FEE = 10000;

    uint32 internal constant TWAP_RANGE_SECS = 1800;
    uint256 public slippage = 9500; // 5%

    constructor(address _vault) BaseStrategy(_vault) {
        ERC20(GMX).approve(STAKED_GMX_TRACKER, type(uint256).max);
        ERC20(ES_GMX).approve(STAKED_GMX_TRACKER, type(uint256).max);
        ERC20(WETH).approve(UNISWAP_V3_ROUTER, type(uint256).max);
        ERC20(GMX).approve(UNISWAP_V3_ROUTER, type(uint256).max);

        want.approve(UNISWAP_V3_ROUTER, type(uint256).max);
    }

    function setSlippage(uint256 _slippage) external onlyStrategist {
        require(_slippage < 10_000, "!_slippage");
        slippage = _slippage;
    }

    function name() external pure override returns (string memory) {
        return "StrategyGMX";
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfUnstakedGmx() public view returns (uint256) {
        return ERC20(GMX).balanceOf(address(this));
    }

    function balanceOfWethRewards() public view returns (uint256) {
        return IRewardTracker(FEE_GMX_TRACKER).claimable(address(this));
    }

    function balanceOfStakedGmx() public view returns (uint256) {
        return
            IRewardTracker(STAKED_GMX_TRACKER).depositBalances(
                address(this),
                GMX
            );
    }

    function balanceOfUnstakedEsGmx() public view returns (uint256) {
        return ERC20(ES_GMX).balanceOf(address(this));
    }

    function balanceOfStakedEsGmx() public view returns (uint256) {
        return
            IRewardTracker(STAKED_GMX_TRACKER).depositBalances(
                address(this),
                ES_GMX
            );
    }

    function _claimWethRewards() internal {
        IRewardRouterV2(GMX_REWARD_ROUTER).handleRewards(
            /* _shouldClaimGmx= */ false,
            /* _shouldStakeGmx= */ false,
            /* _shouldClaimEsGmx= */ false,
            /* _shouldStakeEsGmx= */ false,
            /* _shouldStakeMultiplierPoints= */ false,
            /* _shouldClaimWeth= */ true,
            /* _shouldConvertWethToEth= */ false
        );
    }

    function _withdrawSome(uint256 _amountNeeded) internal {
        if (_amountNeeded == 0) {
            return;
        }

        uint256 _wethBalance = balanceOfWethRewards() +
            ERC20(WETH).balanceOf(address(this));
        if (ethToWant(_wethBalance) >= _amountNeeded) {
            _claimWethRewards();
            _sellWethForWant();
        } else {
            uint256 _gmxToWithdraw = Math.min(
                wantToGmx(_amountNeeded - ethToWant(_wethBalance)),
                balanceOfStakedGmx()
            );
            _exitPosition(_gmxToWithdraw);
        }
    }

    function _sellWethForWant() internal {
        uint256 _wethBalance = ERC20(WETH).balanceOf(address(this));
        if (_wethBalance == 0) {
            return;
        }

        IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter
            .ExactInputParams({
                path: abi.encodePacked(
                    WETH,
                    ETH_USDC_UNI_V3_FEE,
                    address(want)
                ),
                recipient: address(this),
                amountIn: _wethBalance,
                amountOutMinimum: (ethToWant(_wethBalance) * slippage) / 10000
            });
        IV3SwapRouter(UNISWAP_V3_ROUTER).exactInput(params);
    }

    function _exitPosition(uint256 _stakedGmxAmount) internal {
        if (_stakedGmxAmount > 0) {
            _claimWethRewards();
            _sellWethForWant();

            IRewardRouterV2(GMX_REWARD_ROUTER).unstakeGmx(_stakedGmxAmount);
            uint256 _unstakedGmx = balanceOfUnstakedGmx();

            IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter
                .ExactInputParams({
                    path: abi.encodePacked(
                        GMX,
                        ETH_GMX_UNI_V3_FEE,
                        WETH,
                        ETH_USDC_UNI_V3_FEE,
                        address(want)
                    ),
                    recipient: address(this),
                    amountIn: _unstakedGmx,
                    amountOutMinimum: (gmxToWant(_unstakedGmx) * slippage) /
                        10000
                });
            IV3SwapRouter(UNISWAP_V3_ROUTER).exactInput(params);
        }
    }

    function ethToWant(
        uint256 _amtInWei
    ) public view override returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            ETH_USDC_UNI_V3_POOL,
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

    function gmxToWant(uint256 _gmxAmount) public view returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            ETH_GMX_UNI_V3_POOL,
            TWAP_RANGE_SECS
        );
        return
            ethToWant(
                OracleLibrary.getQuoteAtTick(
                    meanTick,
                    uint128(_gmxAmount),
                    GMX,
                    WETH
                )
            );
    }

    function wantToGmx(
        uint256 _wantTokens
    ) public view virtual returns (uint256) {
        uint256 oneGmxPrice = gmxToWant(1 ether);
        uint256 gmxAmountUnscaled = (_wantTokens *
            10 ** ERC20(address(want)).decimals()) / oneGmxPrice;

        return
            Utils.scaleDecimals(
                gmxAmountUnscaled,
                ERC20(address(want)),
                ERC20(GMX)
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
        _wants += gmxToWant(balanceOfUnstakedGmx() + balanceOfStakedGmx());
        _wants += ethToWant(
            balanceOfWethRewards() + ERC20(WETH).balanceOf(address(this))
        );
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
        IRewardRouterV2(GMX_REWARD_ROUTER).handleRewards(
            /* _shouldClaimGmx= */ false,
            /* _shouldStakeGmx= */ false,
            /* _shouldClaimEsGmx= */ true,
            /* _shouldStakeEsGmx= */ true,
            /* _shouldStakeMultiplierPoints= */ true,
            /* _shouldClaimWeth= */ true,
            /* _shouldConvertWethToEth= */ false
        );
        _sellWethForWant();

        uint256 _wantBal = want.balanceOf(address(this));
        if (_wantBal > _debtOutstanding) {
            uint256 _excessWant = _wantBal - _debtOutstanding;

            IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter
                .ExactInputParams({
                    path: abi.encodePacked(
                        address(want),
                        ETH_USDC_UNI_V3_FEE,
                        WETH,
                        ETH_GMX_UNI_V3_FEE,
                        GMX
                    ),
                    recipient: address(this),
                    amountIn: _excessWant,
                    amountOutMinimum: (wantToGmx(_excessWant) * slippage) /
                        10000
                });
            IV3SwapRouter(UNISWAP_V3_ROUTER).exactInput(params);
        }

        // Currently, GMX does not reward users with esGMX and this condition will not be true until
        // they start distributing esGMX rewards.
        if (balanceOfUnstakedEsGmx() > 0) {
            IRewardRouterV2(GMX_REWARD_ROUTER).stakeEsGmx(
                balanceOfUnstakedEsGmx()
            );
        }

        if (balanceOfUnstakedGmx() > 0) {
            IRewardRouterV2(GMX_REWARD_ROUTER).stakeGmx(balanceOfUnstakedGmx());
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        _exitPosition(balanceOfStakedGmx());
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
        IRewardRouterV2(GMX_REWARD_ROUTER).handleRewards(
            /* _shouldClaimGmx= */ false,
            /* _shouldStakeGmx= */ false,
            /* _shouldClaimEsGmx= */ true,
            /* _shouldStakeEsGmx= */ true,
            /* _shouldStakeMultiplierPoints= */ false,
            /* _shouldClaimWeth= */ true,
            /* _shouldConvertWethToEth= */ false
        );
        if (balanceOfStakedGmx() > 0) {
            IRewardRouterV2(GMX_REWARD_ROUTER).unstakeGmx(balanceOfStakedGmx());
        }

        IERC20(WETH).safeTransfer(
            _newStrategy,
            ERC20(WETH).balanceOf(address(this))
        );
        IERC20(GMX).safeTransfer(_newStrategy, balanceOfUnstakedGmx());

        // This is used to allow new strategy to transfer esGMX from old strategy.
        // esGMX is non-transferable by default and we need to signal transfer first.
        IRewardRouterV2(GMX_REWARD_ROUTER).signalTransfer(_newStrategy);
    }

    function acceptTransfer(address _oldStrategy) external onlyStrategist {
        IRewardRouterV2(GMX_REWARD_ROUTER).acceptTransfer(_oldStrategy);
    }

    function protectedTokens()
        internal
        pure
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](3);
        protected[0] = GMX;
        protected[1] = ES_GMX;
        protected[2] = WETH;
        return protected;
    }
}
