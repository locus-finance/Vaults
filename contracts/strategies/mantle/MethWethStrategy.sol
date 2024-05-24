// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libraries/MethWethStrategyLib.sol";

import "../../abstracts/BaseStrategyForSeparatedVault.sol";
import "../../integrations/circuit/ICircuitVault.sol";
import "../../abstracts/mantle/MoeMerchantWithOracleStrategyHelper.sol";

contract MethWethStrategy is
    BaseStrategyForSeparatedVault,
    MoeMerchantWithOracleStrategyHelper
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 public methTokensToAddToMoeLiquidity;
    uint256 public wethTokensToAddToMoeLiquidity;
    uint256 public slippageBps;

    function initialize(
        address _vault,
        address _strategist
    ) external {
        __Base_Strategy_Initialize(
            _vault,
            _strategist,
            _strategist,
            _strategist
        );
        _updateOracle();
        _setWindowSize(1 weeks);
        want.forceApprove(
            address(MoeMerchantLib.MOE_ROUTER),
            type(uint256).max
        );
        want.forceApprove(
            address(AgniSwapLib.AGNI_SWAP_ROUTER),
            type(uint256).max
        );

        MethWethStrategyLib.METH.forceApprove(
            address(MoeMerchantLib.MOE_ROUTER),
            type(uint256).max
        );
        MethWethStrategyLib.WETH.forceApprove(
            address(AgniSwapLib.AGNI_SWAP_ROUTER),
            type(uint256).max
        );
        MethWethStrategyLib.WETH.forceApprove(
            address(MoeMerchantLib.MOE_ROUTER),
            type(uint256).max
        );

        MethWethStrategyLib.MOE_MERCHANT_METH_WETH_POOL.forceApprove(
            address(MoeMerchantLib.MOE_ROUTER),
            type(uint256).max
        );
        MethWethStrategyLib.MOE_MERCHANT_METH_WETH_POOL.forceApprove(
            address(MethWethStrategyLib.CIRCUIT_VAULT),
            type(uint256).max
        );
    }

    function _updateOracle() internal {
        _update(address(want), address(MethWethStrategyLib.METH));
        _update(address(MethWethStrategyLib.METH), address(MethWethStrategyLib.WETH));
    }

    function updateOracle() external onlyAuthorized {
        _updateOracle();
    }

    function setOracleWindowSize(uint256 newWindowSize) external onlyAuthorized {
        _setWindowSize(newWindowSize);
    }

    function setSlippage(uint256 newSlippage) external onlyAuthorized {
        slippageBps = newSlippage;
    }

    function wantToCircuitShares(
        uint256 amount
    ) public view returns (uint256 result) {
        return MethWethStrategyLib.wantToCircuitShares(amount, address(want));
    }

    function circuitSharesToWant(
        uint256 amount
    ) public view returns (uint256 result) {
        return MethWethStrategyLib.circuitSharesToWant(amount, address(want));
    }

    function name() external pure override returns (string memory) {
        return "mETH-WETH Strategy";
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfWeth() public view returns (uint256) {
        return MethWethStrategyLib.WETH.balanceOf(address(this));
    }

    function balanceOfMeth() public view returns (uint256) {
        return MethWethStrategyLib.METH.balanceOf(address(this));
    }

    function balanceOfCircuitShares() public view returns (uint256) {
        return MethWethStrategyLib.CIRCUIT_VAULT.balanceOf(address(this));
    }

    function balanceOfMoeLp() public view returns (uint256) {
        return
            MethWethStrategyLib.MOE_MERCHANT_METH_WETH_POOL.balanceOf(
                address(this)
            );
    }

    function _withdrawSome(uint256 _amountNeeded) internal {
        if (_amountNeeded == 0) {
            return;
        }
        uint256 sharesToWithdraw = Math.min(
            wantToCircuitShares(_amountNeeded),
            balanceOfCircuitShares()
        );
        MethWethStrategyLib.burnShares(
            sharesToWithdraw,
            address(want),
            slippageBps,
            this.balanceOfMoeLp,
            this.balanceOfCircuitShares,
            this.consult
        );
    }

    function estimatedTotalAssets()
        public
        view
        virtual
        override
        returns (uint256 _wants)
    {
        _wants += want.balanceOf(address(this));
        _wants += circuitSharesToWant(balanceOfCircuitShares());
    }

    function prepareReturn(
        uint256 _debtOutstanding
    )
        internal
        override
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    {
        uint256 _totalAssets = estimatedTotalAssets();
        uint256 _totalDebt = vault.getStrategyParams(address(this)).totalDebt;

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
        if (emergencyExit) {
            return;
        }

        uint256 _wantBal = balanceOfWant();
        uint256 _excessWant = 0;
        if (_wantBal > _debtOutstanding) {
            _excessWant = _wantBal - _debtOutstanding;
        }

        if (_excessWant > 0) {
            (
                methTokensToAddToMoeLiquidity,
                wethTokensToAddToMoeLiquidity
            ) = MethWethStrategyLib.mintShares(
                _excessWant,
                address(want),
                methTokensToAddToMoeLiquidity,
                wethTokensToAddToMoeLiquidity,
                slippageBps,
                this.balanceOfMoeLp,
                this.balanceOfCircuitShares,
                this.consult
            );
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        MethWethStrategyLib.burnShares(
            balanceOfCircuitShares(),
            address(want),
            slippageBps,
            this.balanceOfMoeLp,
            this.balanceOfCircuitShares,
            this.consult
        );
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
        uint256 wantBalance = balanceOfWant();
        if (wantBalance > 0) {
            (
                methTokensToAddToMoeLiquidity,
                wethTokensToAddToMoeLiquidity
            ) = MethWethStrategyLib.mintShares(
                wantBalance,
                address(want),
                methTokensToAddToMoeLiquidity,
                wethTokensToAddToMoeLiquidity,
                slippageBps,
                this.balanceOfMoeLp,
                this.balanceOfCircuitShares,
                this.consult
            );
        }
        if (methTokensToAddToMoeLiquidity > 0) {
            MethWethStrategyLib.METH.safeTransfer(
                _newStrategy,
                methTokensToAddToMoeLiquidity
            );
        }
        if (wethTokensToAddToMoeLiquidity > 0) {
            MethWethStrategyLib.WETH.safeTransfer(
                _newStrategy,
                wethTokensToAddToMoeLiquidity
            );
        }
        IERC20(address(MethWethStrategyLib.CIRCUIT_VAULT)).safeTransfer(
            _newStrategy,
            balanceOfCircuitShares()
        );
    }

    function protectedTokens()
        internal
        pure
        override
        returns (address[] memory protected)
    {
        protected = new address[](4);
        protected[0] = address(MethWethStrategyLib.CIRCUIT_VAULT);
        protected[1] = address(MethWethStrategyLib.WETH);
        protected[2] = address(MethWethStrategyLib.METH);
        protected[4] = address(MethWethStrategyLib.MOE_MERCHANT_METH_WETH_POOL);
        return protected;
    }

    receive() external payable {}
}
