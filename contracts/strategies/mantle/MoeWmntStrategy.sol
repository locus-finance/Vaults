// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libraries/MoeWmntStrategyLib.sol";

import "../../abstracts/BaseStrategyForSeparatedVault.sol";
import "../../integrations/circuit/ICircuitVault.sol";
import "../../abstracts/mantle/MoeMerchantWithOracleStrategyHelper.sol";

contract MoeWmntStrategy is
    BaseStrategyForSeparatedVault,
    MoeMerchantWithOracleStrategyHelper
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 public moeTokensToAddToMoeLiquidity;
    uint256 public wmntTokensToAddToMoeLiquidity;
    uint256 public slippageBps;
    uint32 public agniTwapRangeSecs;

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
        slippageBps = 9000;
        agniTwapRangeSecs = 1 days;
        want.forceApprove(
            address(MoeMerchantLib.MOE_ROUTER),
            type(uint256).max
        );
        MoeWmntStrategyLib.USDT.forceApprove(
            address(MoeMerchantLib.MOE_ROUTER),
            type(uint256).max
        );
        MoeWmntStrategyLib.MOE.forceApprove(
            address(MoeMerchantLib.MOE_ROUTER),
            type(uint256).max
        );
        want.forceApprove(
            address(AgniSwapLib.AGNI_SWAP_ROUTER),
            type(uint256).max
        );
        MoeWmntStrategyLib.WMNT.forceApprove(
            address(AgniSwapLib.AGNI_SWAP_ROUTER),
            type(uint256).max
        );
        MoeWmntStrategyLib.MOE_MERCHANT_MOE_WMNT_POOL.forceApprove(
            address(MoeMerchantLib.MOE_ROUTER),
            type(uint256).max
        );
        MoeWmntStrategyLib.MOE_MERCHANT_MOE_WMNT_POOL.forceApprove(
            address(MoeWmntStrategyLib.CIRCUIT_VAULT),
            type(uint256).max
        );
    }

    function _updateOracle() internal {
        _update(address(want), address(MoeWmntStrategyLib.USDT));
        _update(
            address(MoeWmntStrategyLib.USDT),
            address(MoeWmntStrategyLib.MOE)
        );
        _update(
            address(MoeWmntStrategyLib.MOE),
            address(MoeWmntStrategyLib.WMNT)
        );
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

    function setAgniTwapRangeSecs(uint32 newAgniTwapRangeSecs) external onlyAuthorized {
        agniTwapRangeSecs = newAgniTwapRangeSecs;
    }

    function name() external pure override returns (string memory) {
        return "MOE-WMNT Strategy";
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfWmnt() public view returns (uint256) {
        return MoeWmntStrategyLib.WMNT.balanceOf(address(this));
    }

    function balanceOfUsdt() public view returns (uint256) {
        return MoeWmntStrategyLib.USDT.balanceOf(address(this));
    }

    function balanceOfMoe() public view returns (uint256) {
        return MoeWmntStrategyLib.MOE.balanceOf(address(this));
    }

    function balanceOfCircuitShares() public view returns (uint256) {
        return MoeWmntStrategyLib.CIRCUIT_VAULT.balanceOf(address(this));
    }

    function balanceOfMoeLp() public view returns (uint256) {
        return
            MoeWmntStrategyLib.MOE_MERCHANT_MOE_WMNT_POOL.balanceOf(
                address(this)
            );
    }

    function wantToCircuitShares(
        uint256 amount
    ) public view returns (uint256 result) {
        return MoeWmntStrategyLib.wantToCircuitShares(amount, address(want), agniTwapRangeSecs);
    }

    function circuitSharesToWant(
        uint256 amount
    ) public view returns (uint256 result) {
        return MoeWmntStrategyLib.circuitSharesToWant(amount, address(want), agniTwapRangeSecs);
    }

    function _withdrawSome(uint256 _amountNeeded) internal {
        if (_amountNeeded == 0) {
            return;
        }
        uint256 sharesToWithdraw = Math.min(
            wantToCircuitShares(_amountNeeded),
            balanceOfCircuitShares()
        );
        MoeWmntStrategyLib.burnShares(
            sharesToWithdraw,
            address(want),
            slippageBps,
            agniTwapRangeSecs,
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
                moeTokensToAddToMoeLiquidity,
                wmntTokensToAddToMoeLiquidity
            ) = MoeWmntStrategyLib.mintShares(
                _excessWant,
                address(want),
                moeTokensToAddToMoeLiquidity,
                wmntTokensToAddToMoeLiquidity,
                slippageBps,
                agniTwapRangeSecs,
                this.balanceOfMoeLp,
                this.balanceOfCircuitShares,
                this.consult
            );
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        MoeWmntStrategyLib.burnShares(
            balanceOfCircuitShares(),
            address(want),
            slippageBps,
            agniTwapRangeSecs,
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
                moeTokensToAddToMoeLiquidity,
                wmntTokensToAddToMoeLiquidity
            ) = MoeWmntStrategyLib.mintShares(
                wantBalance,
                address(want),
                moeTokensToAddToMoeLiquidity,
                wmntTokensToAddToMoeLiquidity,
                slippageBps,
                agniTwapRangeSecs,
                this.balanceOfMoeLp,
                this.balanceOfCircuitShares,
                this.consult
            );
        }
        if (moeTokensToAddToMoeLiquidity > 0) {
            MoeWmntStrategyLib.MOE.safeTransfer(
                _newStrategy,
                moeTokensToAddToMoeLiquidity
            );
        }
        if (wmntTokensToAddToMoeLiquidity > 0) {
            MoeWmntStrategyLib.WMNT.safeTransfer(
                _newStrategy,
                wmntTokensToAddToMoeLiquidity
            );
        }
        IERC20(address(MoeWmntStrategyLib.CIRCUIT_VAULT)).safeTransfer(
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
        protected = new address[](5);
        protected[0] = address(MoeWmntStrategyLib.CIRCUIT_VAULT);
        protected[1] = address(MoeWmntStrategyLib.MOE);
        protected[2] = address(MoeWmntStrategyLib.USDT);
        protected[3] = address(MoeWmntStrategyLib.WMNT);
        protected[4] = address(MoeWmntStrategyLib.MOE_MERCHANT_MOE_WMNT_POOL);
        return protected;
    }

    receive() external payable {}
}
