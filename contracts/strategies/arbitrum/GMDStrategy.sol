// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {BaseStrategy, StrategyParams, VaultAPI} from "@yearn-protocol/contracts/BaseStrategy.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

import "../../integrations/uniswap/v3/IV3SwapRouter.sol";
import "../../integrations/gmd/IGMDStaking.sol";

import "../../utils/Utils.sol";

contract GMDStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    address internal constant GMD = 0x4945970EfeEc98D393b4b979b9bE265A3aE28A8B;
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    uint256 internal constant GMD_PID = 0;
    address internal constant GMD_POOL =
        0x48C81451D1FDdecA84b47ff86F91708fa5c32e93;
    address internal constant UNISWAP_V3_ROUTER =
        0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    address internal constant ETH_USDC_UNI_V3_POOL =
        0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443;
    address internal constant GMD_ETH_UNI_V3_POOL =
        0x0632742C132413Cd47438691D8064Ff9214aC216;

    uint24 internal constant ETH_USDC_UNI_FEE = 500;
    uint24 internal constant GMD_ETH_UNI_FEE = 3000;

    uint32 internal constant TWAP_RANGE_SECS = 1800;

    uint256 public slippage = 9900; // 1%

    constructor(address _vault) BaseStrategy(_vault) {
        want.safeApprove(UNISWAP_V3_ROUTER, type(uint256).max);
        IERC20(WETH).safeApprove(UNISWAP_V3_ROUTER, type(uint256).max);
        IERC20(GMD).safeApprove(UNISWAP_V3_ROUTER, type(uint256).max);
        IERC20(GMD).safeApprove(GMD_POOL, type(uint256).max);
    }

    function setSlippage(uint256 _slippage) external onlyStrategist {
        require(_slippage < 10_000, "!_slippage");
        slippage = _slippage;
    }

    function name() external pure override returns (string memory) {
        return "StrategyGMD";
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfWeth() public view returns (uint256) {
        return IERC20(WETH).balanceOf(address(this));
    }

    function balanceOfGmd() public view returns (uint256) {
        return IERC20(GMD).balanceOf(address(this));
    }

    function balanceOfStakedGmd() public view returns (uint256) {
        (, uint256 amount, , ) = IGMDStaking(GMD_POOL).userInfo(
            GMD_PID,
            address(this)
        );
        return amount;
    }

    function balanceOfRewards() public view returns (uint256) {
        return IGMDStaking(GMD_POOL).pendingWETH(GMD_PID, address(this));
    }

    function _withdrawSome(uint256 _amountNeeded) internal {
        if (_amountNeeded == 0) return;

        uint256 rewardsTotal = ethToWant(balanceOfRewards());
        if (rewardsTotal >= _amountNeeded) {
            _sellRewards();
            return;
        }

        uint256 gmdToUnstake = Math.min(
            balanceOfStakedGmd(),
            wantToGmd(_amountNeeded - rewardsTotal)
        );

        _exitPosition(gmdToUnstake);
    }

    function _sellRewards() internal {
        // the only way to get rewards from MasterChef is deposit or withdraw
        IGMDStaking(GMD_POOL).deposit(GMD_PID, 0);

        uint256 balWeth = IERC20(WETH).balanceOf(address(this));
        if (balWeth > 0) {
            uint256 minAmountOut = (ethToWant(balWeth) * slippage) / 10000;
            IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter
                .ExactInputSingleParams({
                    tokenIn: WETH,
                    tokenOut: address(want),
                    fee: ETH_USDC_UNI_FEE,
                    recipient: address(this),
                    amountIn: balWeth,
                    amountOutMinimum: minAmountOut,
                    sqrtPriceLimitX96: 0
                });
            IV3SwapRouter(UNISWAP_V3_ROUTER).exactInputSingle(params);
        }
    }

    function _exitPosition(uint256 gmdAmount) internal {
        _sellRewards();

        if (gmdAmount == 0) {
            return;
        }

        IGMDStaking(GMD_POOL).withdraw(GMD_PID, gmdAmount);

        uint256 minAmountOut = (gmdToWant(gmdAmount) * slippage) / 10000;
        IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter
            .ExactInputParams({
                path: abi.encodePacked(
                    GMD,
                    GMD_ETH_UNI_FEE,
                    WETH,
                    ETH_USDC_UNI_FEE,
                    address(want)
                ),
                recipient: address(this),
                amountIn: gmdAmount,
                amountOutMinimum: minAmountOut
            });
        IV3SwapRouter(UNISWAP_V3_ROUTER).exactInput(params);
    }

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

    function wantToEth(uint256 wantAmount) public view returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            ETH_USDC_UNI_V3_POOL,
            TWAP_RANGE_SECS
        );
        return
            OracleLibrary.getQuoteAtTick(
                meanTick,
                uint128(wantAmount),
                address(want),
                WETH
            );
    }

    function gmdToWant(uint256 gmdAmount) public view returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            GMD_ETH_UNI_V3_POOL,
            TWAP_RANGE_SECS
        );
        return
            ethToWant(
                OracleLibrary.getQuoteAtTick(
                    meanTick,
                    uint128(gmdAmount),
                    GMD,
                    address(WETH)
                )
            );
    }

    function wantToGmd(uint256 wantAmount) public view returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            GMD_ETH_UNI_V3_POOL,
            TWAP_RANGE_SECS
        );
        return
            OracleLibrary.getQuoteAtTick(
                meanTick,
                uint128(wantToEth(wantAmount)),
                address(WETH),
                GMD
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
        _wants += gmdToWant(balanceOfGmd());
        _wants += gmdToWant(balanceOfStakedGmd());
        _wants += ethToWant(balanceOfWeth());
        _wants += ethToWant(balanceOfRewards());
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

        uint256 _liquidWant = balanceOfWant();
        uint256 _amountNeeded = _debtOutstanding + _profit;
        if (_liquidWant <= _amountNeeded) {
            _withdrawSome(_amountNeeded - _liquidWant);
            _liquidWant = balanceOfWant();
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

    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }

        _sellRewards();

        uint256 _wantBal = balanceOfWant();
        if (_wantBal > _debtOutstanding) {
            uint256 _excessWant = _wantBal - _debtOutstanding;
            uint256 minAmountOut = (wantToGmd(_excessWant) * slippage) / 10000;
            IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter
                .ExactInputParams({
                    path: abi.encodePacked(
                        address(want),
                        ETH_USDC_UNI_FEE,
                        WETH,
                        GMD_ETH_UNI_FEE,
                        GMD
                    ),
                    recipient: address(this),
                    amountIn: _excessWant,
                    amountOutMinimum: minAmountOut
                });
            IV3SwapRouter(UNISWAP_V3_ROUTER).exactInput(params);
        }

        uint256 gmdBal = balanceOfGmd();
        if (gmdBal > 0) {
            IGMDStaking(GMD_POOL).deposit(GMD_PID, gmdBal);
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        _exitPosition(balanceOfStakedGmd());
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
        IGMDStaking(GMD_POOL).withdraw(GMD_PID, balanceOfStakedGmd());
        IERC20(GMD).safeTransfer(_newStrategy, balanceOfGmd());
        IERC20(WETH).safeTransfer(_newStrategy, balanceOfWeth());
    }

    function protectedTokens()
        internal
        pure
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](2);
        protected[0] = GMD;
        protected[1] = WETH;
        return protected;
    }
}
