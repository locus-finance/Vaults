// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libraries/LendWmntStrategyLib.sol";

import "../../abstracts/BaseStrategyForSeparatedVault.sol";
import "../../integrations/circuit/ICircuitVault.sol";
import "../../abstracts/mantle/MoeMerchantWithOracleStrategyHelper.sol";
import "../../abstracts/mantle/AgniMultihopOpsStrategyHelper.sol";

contract LendWmntStrategy is
    BaseStrategyForSeparatedVault,
    MoeMerchantWithOracleStrategyHelper,
    AgniMultihopOpsStrategyHelper
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 public lendTokensToAddToMoeLiquidity;
    uint256 public wmntTokensToAddToMoeLiquidity;
    uint256 public slippageBps;
    uint32 public agniTwapRangeSecs;

    function initialize(address _vault, address _strategist) external {
        __Base_Strategy_Initialize(
            _vault,
            _strategist,
            _strategist,
            _strategist
        );
        _setWindowSize(1 weeks);
        slippageBps = 9000;
        agniTwapRangeSecs = 1 days;
        _initializeAgniSwapStrategyHelper(
            address(want),
            address(LendWmntStrategyLib.USDT),
            address(LendWmntStrategyLib.WETH),
            address(LendWmntStrategyLib.WMNT),
            LendWmntStrategyLib.STANDARD_AGNI_FEE_USDC_USDT,
            LendWmntStrategyLib.STANDARD_AGNI_FEE_USDT_WETH,
            LendWmntStrategyLib.STANDARD_AGNI_FEE_WETH_WMNT
        );

        want.forceApprove(
            address(MoeMerchantLib.MOE_ROUTER),
            type(uint256).max
        );
        LendWmntStrategyLib.WMNT.forceApprove(
            address(MoeMerchantLib.MOE_ROUTER),
            type(uint256).max
        );
        LendWmntStrategyLib.LEND.forceApprove(
            address(MoeMerchantLib.MOE_ROUTER),
            type(uint256).max
        );
        LendWmntStrategyLib.USDT.forceApprove(
            address(MoeMerchantLib.MOE_ROUTER),
            type(uint256).max
        );

        want.forceApprove(
            address(AgniSwapLib.AGNI_SWAP_ROUTER),
            type(uint256).max
        );
        LendWmntStrategyLib.WMNT.forceApprove(
            address(AgniSwapLib.AGNI_SWAP_ROUTER),
            type(uint256).max
        );
        LendWmntStrategyLib.LEND.forceApprove(
            address(AgniSwapLib.AGNI_SWAP_ROUTER),
            type(uint256).max
        );
        LendWmntStrategyLib.USDT.forceApprove(
            address(AgniSwapLib.AGNI_SWAP_ROUTER),
            type(uint256).max
        );
        LendWmntStrategyLib.WETH.forceApprove(
            address(AgniSwapLib.AGNI_SWAP_ROUTER),
            type(uint256).max
        );
        LendWmntStrategyLib.WMNT.forceApprove(
            address(AgniSwapLib.AGNI_SWAP_ROUTER),
            type(uint256).max
        );

        LendWmntStrategyLib.MOE_MERCHANT_LEND_WMNT_POOL.forceApprove(
            address(MoeMerchantLib.MOE_ROUTER),
            type(uint256).max
        );
        LendWmntStrategyLib.MOE_MERCHANT_LEND_WMNT_POOL.forceApprove(
            address(LendWmntStrategyLib.CIRCUIT_VAULT),
            type(uint256).max
        );
    }

    function _updateOracle() internal {
        LendWmntStrategyLib.updateTraces(
            address(want),
            this.update
        );
    }

    function updateOracle() public onlyAuthorized {
        _updateOracle();
    }

    function setOracleWindowSize(
        uint256 newWindowSize
    ) external onlyAuthorized {
        _setWindowSize(newWindowSize);
    }

    function setSlippage(uint256 newSlippage) external onlyAuthorized {
        slippageBps = newSlippage;
    }

    function setAgniTwapRangeSecs(
        uint32 newAgniTwapRangeSecs
    ) external onlyAuthorized {
        agniTwapRangeSecs = newAgniTwapRangeSecs;
    }

    function name() external pure override returns (string memory) {
        return "LEND-WMNT Strategy";
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfLend() public view returns (uint256) {
        return LendWmntStrategyLib.LEND.balanceOf(address(this));
    }

    function balanceOfWmnt() public view returns (uint256) {
        return LendWmntStrategyLib.WMNT.balanceOf(address(this));
    }

    function balanceOfCircuitShares() public view returns (uint256) {
        return LendWmntStrategyLib.CIRCUIT_VAULT.balanceOf(address(this));
    }

    function balanceOfMoeLp() public view returns (uint256) {
        return
            LendWmntStrategyLib.MOE_MERCHANT_LEND_WMNT_POOL.balanceOf(
                address(this)
            );
    }

    function wantToCircuitShares(
        uint256 amount
    ) public view returns (uint256 result) {
        return
            LendWmntStrategyLib.wantToCircuitShares(
                amount,
                address(want),
                agniTwapRangeSecs,
                this.usdcToWmntQuote
            );
    }

    function circuitSharesToWant(
        uint256 amount
    ) public view returns (uint256 result) {
        return
            LendWmntStrategyLib.circuitSharesToWant(
                amount,
                address(want),
                agniTwapRangeSecs,
                this.wmntToUsdcQuote
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
        LendWmntStrategyLib.burnShares(
            sharesToWithdraw,
            address(want),
            slippageBps,
            agniTwapRangeSecs,
            this.balanceOfMoeLp,
            this.balanceOfCircuitShares,
            this.consult,
            this.wmntToUsdcSwap
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
                lendTokensToAddToMoeLiquidity,
                wmntTokensToAddToMoeLiquidity
            ) = LendWmntStrategyLib.mintShares(
                _excessWant,
                address(want),
                lendTokensToAddToMoeLiquidity,
                wmntTokensToAddToMoeLiquidity,
                slippageBps,
                agniTwapRangeSecs,
                this.balanceOfMoeLp,
                this.balanceOfCircuitShares,
                this.consult,
                this.usdcToWmntSwap
            );
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        LendWmntStrategyLib.burnShares(
            balanceOfCircuitShares(),
            address(want),
            slippageBps,
            agniTwapRangeSecs,
            this.balanceOfMoeLp,
            this.balanceOfCircuitShares,
            this.consult,
            this.wmntToUsdcSwap
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
                lendTokensToAddToMoeLiquidity,
                wmntTokensToAddToMoeLiquidity
            ) = LendWmntStrategyLib.mintShares(
                wantBalance,
                address(want),
                lendTokensToAddToMoeLiquidity,
                wmntTokensToAddToMoeLiquidity,
                slippageBps,
                agniTwapRangeSecs,
                this.balanceOfMoeLp,
                this.balanceOfCircuitShares,
                this.consult,
                this.usdcToWmntSwap
            );
        }
        if (lendTokensToAddToMoeLiquidity > 0) {
            LendWmntStrategyLib.LEND.safeTransfer(
                _newStrategy,
                lendTokensToAddToMoeLiquidity
            );
        }
        if (wmntTokensToAddToMoeLiquidity > 0) {
            LendWmntStrategyLib.WMNT.safeTransfer(
                _newStrategy,
                wmntTokensToAddToMoeLiquidity
            );
        }
        IERC20(address(LendWmntStrategyLib.CIRCUIT_VAULT)).safeTransfer(
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
        protected[0] = address(LendWmntStrategyLib.CIRCUIT_VAULT);
        protected[1] = address(LendWmntStrategyLib.LEND);
        protected[2] = address(LendWmntStrategyLib.WMNT);
        protected[3] = address(LendWmntStrategyLib.MOE_MERCHANT_LEND_WMNT_POOL);
        return protected;
    }

    receive() external payable {}
}
