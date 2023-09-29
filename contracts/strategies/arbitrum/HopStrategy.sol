// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { BaseStrategy, StrategyParams, VaultAPI } from "@yearn-protocol/contracts/BaseStrategy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { OracleLibrary } from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "hardhat/console.sol";

import "../../integrations/hop/IStakingRewards.sol";
import "../../integrations/hop/IRouter.sol";

contract HopStrategy is BaseStrategy, Initializable {
    using SafeERC20 for IERC20;

    uint8 internal constant USDCindex = 0;
    uint8 internal constant USDCLPindex = 1;
    address internal constant HOP_ROUTER =
        0x10541b07d8Ad2647Dc6cD67abd4c03575dade261;
    address internal constant STAKING_REWARD =
        0xb0CabFE930642AD3E7DECdc741884d8C3F7EbC70;
    address internal constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address internal constant LP = 0xB67c014FA700E69681a673876eb8BAFAA36BFf71;
    address internal constant HOP = 0xc5102fE9359FD9a28f877a67E36B0F050d81a3CC;

    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address internal constant HOP_WETH_UNI_POOL =
        0x44ca2BE2Bd6a7203CCDBb63EED8382274f737A15;
    address internal constant WETH_USDC_UNI_POOL =
        0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443;
    uint256 internal constant HOP_WETH_POOL_FEE = 3000;
    uint256 internal constant USDC_WETH_POOL_FEE = 500;
    address internal constant UNISWAP_V3_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;

    uint32 internal constant TWAP_RANGE_SECS = 1800;

    uint256 internal constant slippage = 9500;
    address internal constant ETH_USDC_UNI_V3_POOL =
        0xC6962004f452bE9203591991D15f6b388e09E8D0;

    function ethToWant(
        uint256 ethAmount
    ) public view override returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            ETH_USDC_UNI_V3_POOL,
            TWAP_RANGE_SECS
        );
        return
            OracleLibrary.getQuoteAtTick(
                meanTick,
                uint128(ethAmount),
                WETH,
                address(want)
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
        console.log(_totalAssets, _totalDebt);
        if (_totalAssets >= _totalDebt) {
            _profit = _totalAssets - _totalDebt;
            _loss = 0;
        } else {
            _profit = 0;
            _loss = _totalDebt - _totalAssets;
        }

        uint256 _liquidWant = want.balanceOf(address(this));
        uint256 _amountNeeded = _debtOutstanding + _profit;
        console.log("PROFIT", _profit);
        console.log(_liquidWant, _amountNeeded);
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
        // protected[0] = GNS;
        // protected[1] = DAI;
        // protected[2] = WETH;
        return protected;
    }

    function initialize(
        address _vault,
        address _strategist
    ) public initializer {
        _initialize(_vault, _strategist, _strategist, _strategist);

        IERC20(LP).safeApprove(STAKING_REWARD, type(uint256).max);
        IERC20(LP).safeApprove(HOP_ROUTER, type(uint256).max);
        IERC20(HOP).safeApprove(UNISWAP_V3_ROUTER, type(uint256).max);
        want.safeApprove(HOP_ROUTER, type(uint256).max);
    }

    constructor(address _vault) BaseStrategy(_vault) {}

    function name() external pure override returns (string memory) {
        return "HopStrategy";
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return
            LpToWant(balanceOfStaked()) +
            balanceOfUnstaked() +
            HopToWant(rewardss());
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }
        console.log("BEFORE CLAIM");
        _claimAndSellRewards();
        console.log("AFTER CLAIM");
        uint256 unstakedBalance = balanceOfUnstaked();

        uint256 excessWant;
        if (unstakedBalance > _debtOutstanding) {
            excessWant = unstakedBalance - _debtOutstanding;
        }
        console.log("ADJUST", unstakedBalance, _debtOutstanding, excessWant);
        if (excessWant > 0) {
            uint256[] memory liqAmounts = new uint256[](2);
            liqAmounts[0] = excessWant;
            liqAmounts[1] = 0;
            uint256 minAmount = (IRouter(HOP_ROUTER).calculateTokenAmount(
                address(this),
                liqAmounts,
                true
            ) * slippage) / 10000;

            console.log(liqAmounts[0], minAmount);

            IRouter(HOP_ROUTER).addLiquidity(
                liqAmounts,
                minAmount,
                block.timestamp
            );
            uint256 lpBalance = IERC20(LP).balanceOf(address(this));
            console.log(lpBalance);
            IStakingRewards(STAKING_REWARD).stake(lpBalance);
        }
    }

    function liquidatePosition(
        uint256 _amountNeeded
    ) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {
        uint256 _wantBal = want.balanceOf(address(this));
        if (_wantBal >= _amountNeeded) {
            return (_amountNeeded, 0);
        }
        console.log("IF STATEMENT", _wantBal, _amountNeeded);
        _withdrawSome(_amountNeeded - _wantBal);
        console.log("AFTER WITHDRAW SOME");
        _wantBal = want.balanceOf(address(this));

        if (_amountNeeded > _wantBal) {
            _liquidatedAmount = _wantBal;
            _loss = _amountNeeded - _wantBal;
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }
    //minAmount problem
    function liquidateAllPositions()
        internal
        override
        returns (uint256 _amountFreed)
    {
        _claimAndSellRewards();

        uint256 stakingAmount = balanceOfStaked();
        IStakingRewards(STAKING_REWARD).withdraw(stakingAmount);
        IRouter(HOP_ROUTER).removeLiquidityOneToken(
            stakingAmount,
            0,
            0,
            block.timestamp
        );
        _amountFreed = want.balanceOf(address(this));
    }

    function prepareMigration(address _newStrategy) internal override {
        uint256 assets = liquidateAllPositions();
        want.safeTransfer(_newStrategy, assets);
    }

    function balanceOfStaked() public view returns (uint256 amount) {
        amount = IStakingRewards(STAKING_REWARD).balanceOf(address(this));
    }

    function balanceOfUnstaked() public view returns (uint256 amount) {
        amount = want.balanceOf(address(this));
    }

    function rewardss() public view returns (uint256 amount) {
        console.log(
            "BALANCE",
            IStakingRewards(STAKING_REWARD).balanceOf(address(this))
        );
        amount = IStakingRewards(STAKING_REWARD).earned(address(this));
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

    function LpToWant(
        uint256 amountIn
    ) public view returns (uint256 amountOut) {
        if (amountIn == 0) {
            return 0;
        }
        amountOut = IRouter(HOP_ROUTER).calculateRemoveLiquidityOneToken(
            address(this),
            amountIn,
            0
        );
    }

    function HopToWant(
        uint256 amountIn
    ) public view returns (uint256 amountOut) {
        amountOut = smthToSmth(
            WETH_USDC_UNI_POOL,
            WETH,
            address(want),
            smthToSmth(HOP_WETH_UNI_POOL, HOP, WETH, amountIn)
        );
    }

    function _withdrawSome(uint256 _amountNeeded) internal {
        if (_amountNeeded == 0) {
            return;
        }
        if (HopToWant(rewardss()) >= _amountNeeded) {
            _claimAndSellRewards();
        } else {
            uint256 _usdcToUnstake = Math.min(
                balanceOfStaked(),
                _amountNeeded - HopToWant(rewardss())
            );
            _exitPosition(_usdcToUnstake);
        }
    }

    function _claimAndSellRewards() internal {
        IStakingRewards(STAKING_REWARD).getReward();
        console.log("BEFORE SELL");
        _sellHopForWant(IERC20(HOP).balanceOf(address(this)));
        console.log("AFTER SELL");
    }

    function _exitPosition(uint256 _stakedAmount) internal {
        _claimAndSellRewards();
        uint256[] memory amountsToWithdraw = new uint256[](2);
        amountsToWithdraw[0] = _stakedAmount;
        amountsToWithdraw[1] = 0;
        console.log("STAKED AMOUNT", _stakedAmount);

        uint256 amountLpToWithdraw = IRouter(HOP_ROUTER).calculateTokenAmount(
            address(this),
            amountsToWithdraw,
            false
        );
        if (amountLpToWithdraw > balanceOfStaked()) {
            amountLpToWithdraw = balanceOfStaked();
        }
        console.log("STAKING BALANCE",IStakingRewards(STAKING_REWARD).balanceOf(address(this)));
        console.log(amountLpToWithdraw);
        IStakingRewards(STAKING_REWARD).withdraw(amountLpToWithdraw);
        uint256 minAmount = (_stakedAmount * slippage) / 10000;
        console.log("MIN AMOUNT", minAmount);
        console.log("AMOUNT LP TO WITHDRAW", amountLpToWithdraw);
        IRouter(HOP_ROUTER).removeLiquidityOneToken(
            amountLpToWithdraw,
            0,
            minAmount,
            block.timestamp
        );
        console.log("FINISHED");
    }

    

    function _sellHopForWant(uint256 amountToSell) internal {
        if (amountToSell == 0) {
            return;
        }
        console.log("STRANGE!!!!!");
        ISwapRouter.ExactInputParams memory params;
        bytes memory swapPath = abi.encodePacked(
            HOP,
            uint24(HOP_WETH_POOL_FEE),
            WETH,
            uint24(USDC_WETH_POOL_FEE),
            USDC
        );

        uint256 usdcExpected = HopToWant(amountToSell);
        params.path = swapPath;
        params.recipient = address(this);
        params.deadline = block.timestamp;
        params.amountIn = amountToSell;
        params.amountOutMinimum = (usdcExpected * slippage) / 10000;
        console.log("BEFORE SWAP", amountToSell, usdcExpected);
        ISwapRouter(UNISWAP_V3_ROUTER).exactInput(params);
        console.log("AFTER SWAP");
    }
}
