// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libraries/UsdcUsdyStrategyLib.sol";

import "../../abstracts/BaseStrategyForSeparatedVault.sol";
import "../../integrations/circuit/ICircuitVault.sol";
import "../../abstracts/mantle/MoeMerchantWithOracleStrategyHelper.sol";

contract UsdcUsdyStrategy is
    BaseStrategyForSeparatedVault,
    MoeMerchantWithOracleStrategyHelper
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 public wantTokensToAddToMoeLiquidity;
    uint256 public usdyTokensToAddToMoeLiquidity;

    function initialize(
        address _vault,
        address _strategist,
        uint256 oracleWindowSize,
        uint8 oracleGranularity
    ) external {
        __Base_Strategy_Initialize(
            _vault,
            _strategist,
            _strategist,
            _strategist
        );
        _initializeMoeMerchantHelperWithOracle(
            oracleWindowSize,
            oracleGranularity
        );
        want.forceApprove(
            address(MoeMerchantLib.MOE_ROUTER),
            type(uint256).max
        );
        UsdcUsdyStrategyLib.USDY.forceApprove(
            address(MoeMerchantLib.MOE_ROUTER),
            type(uint256).max
        );
        UsdcUsdyStrategyLib.MOE_MERCHANT_USDC_USDY_POOL.forceApprove(
            address(MoeMerchantLib.MOE_ROUTER),
            type(uint256).max
        );
        UsdcUsdyStrategyLib.MOE_MERCHANT_USDC_USDY_POOL.forceApprove(
            address(UsdcUsdyStrategyLib.CIRCUIT_VAULT),
            type(uint256).max
        );
    }

    function resetOracle(
        uint256 oracleWindowSize,
        uint8 oracleGranularity
    ) external onlyAuthorized {
        if (oracleWindowSize == 0) {
            oracleWindowSize = 1 weeks;
        }
        if (oracleGranularity == 0) {
            oracleGranularity = 3;
        }
        _initializeMoeMerchantHelperWithOracle(
            oracleWindowSize,
            oracleGranularity
        );
    }

    function updateOracle() external onlyAuthorized {
        _update(address(want), address(UsdcUsdyStrategyLib.USDY));
    }

    function name() external pure override returns (string memory) {
        return "USDC-USDY Strategy";
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfUsdy() public view returns (uint256) {
        return UsdcUsdyStrategyLib.USDY.balanceOf(address(this));
    }

    function balanceOfCircuitShares() public view returns (uint256) {
        return UsdcUsdyStrategyLib.CIRCUIT_VAULT.balanceOf(address(this));
    }

    function balanceOfMoeLp() public view returns (uint256) {
        return
            UsdcUsdyStrategyLib.MOE_MERCHANT_USDC_USDY_POOL.balanceOf(
                address(this)
            );
    }

    function wantToCircuitShares(
        uint256 amount
    ) public view returns (uint256 result) {
        return UsdcUsdyStrategyLib.wantToCircuitShares(amount, address(want));
    }

    function circuitSharesToWant(
        uint256 amount
    ) public view returns (uint256 result) {
        return UsdcUsdyStrategyLib.circuitSharesToWant(amount, address(want));
    }

    function _withdrawSome(uint256 _amountNeeded) internal {
        if (_amountNeeded == 0) {
            return;
        }
        uint256 sharesToWithdraw = Math.min(
            wantToCircuitShares(_amountNeeded),
            balanceOfCircuitShares()
        );
        UsdcUsdyStrategyLib.burnShares(
            sharesToWithdraw,
            address(want),
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
                wantTokensToAddToMoeLiquidity,
                usdyTokensToAddToMoeLiquidity
            ) = UsdcUsdyStrategyLib.mintShares(
                _excessWant,
                address(want),
                wantTokensToAddToMoeLiquidity,
                usdyTokensToAddToMoeLiquidity,
                this.balanceOfMoeLp,
                this.balanceOfCircuitShares,
                this.consult
            );
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        UsdcUsdyStrategyLib.burnShares(
            balanceOfCircuitShares(),
            address(want),
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
                wantTokensToAddToMoeLiquidity,
                usdyTokensToAddToMoeLiquidity
            ) = UsdcUsdyStrategyLib.mintShares(
                wantBalance,
                address(want),
                wantTokensToAddToMoeLiquidity,
                usdyTokensToAddToMoeLiquidity,
                this.balanceOfMoeLp,
                this.balanceOfCircuitShares,
                this.consult
            );
        }
        if (wantTokensToAddToMoeLiquidity > 0) {
            want.safeTransfer(_newStrategy, wantTokensToAddToMoeLiquidity);
        }
        if (usdyTokensToAddToMoeLiquidity > 0) {
            UsdcUsdyStrategyLib.USDY.safeTransfer(
                _newStrategy,
                usdyTokensToAddToMoeLiquidity
            );
        }
        IERC20(address(UsdcUsdyStrategyLib.CIRCUIT_VAULT)).safeTransfer(
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
        protected = new address[](3);
        protected[0] = address(UsdcUsdyStrategyLib.CIRCUIT_VAULT);
        protected[1] = address(UsdcUsdyStrategyLib.USDY);
        protected[2] = address(UsdcUsdyStrategyLib.MOE_MERCHANT_USDC_USDY_POOL);
        return protected;
    }

    receive() external payable {}
}
