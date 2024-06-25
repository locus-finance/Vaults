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

    /// @dev DEPRECATED - DO NOT USE AND DO NOT DELETE TO PREVENT THE STORAGE RIFF-RAFF.
    uint256 public moeTokensToAddToMoeLiquidity;

    /// @dev DEPRECATED - DO NOT USE AND DO NOT DELETE TO PREVENT THE STORAGE RIFF-RAFF.
    uint256 public wmntTokensToAddToMoeLiquidity;

    uint256 public slippageBps;

    event WithdrawnWithMoe(
        uint256 indexed amountMoeSwapped,
        uint256 indexed amountUsdcSwappedTo
    );
    event WithdrawnWithWmnt(
        uint256 indexed amountWmntSwapped,
        uint256 indexed amountUsdcSwappedTo
    );
    event WithdrawnWithMoeAndWmnt(
        uint256 indexed amountMoeSwapped,
        uint256 indexed amountWmntSwapped,
        uint256 indexed wantTokensLeft,
        uint256 amountUsdcSwappedFromMoe,
        uint256 amountUsdcSwappedFromWmnt
    );
    event WithdrawnWithSharesBurnAndSwaps(
        uint256 indexed amountMoeSwapped,
        uint256 indexed amountWmntSwapped,
        uint256 indexed sharesBurnt,
        uint256 amountUsdcSwappedFromMoe,
        uint256 amountUsdcSwappedFromWmnt
    );

    function initialize(address _vault, address _strategist) external {
        __Base_Strategy_Initialize(
            _vault,
            _strategist,
            _strategist,
            _strategist
        );
        _setWindowSize(1 weeks);
        slippageBps = 9000;
        _resetAllowances();
    }

    function _resetAllowances() internal {
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
        MoeWmntStrategyLib.WMNT.forceApprove(
            address(MoeMerchantLib.MOE_ROUTER),
            type(uint256).max
        );

        MoeWmntStrategyLib.MOE.forceApprove(
            address(MoeWmntStrategyLib.MOE_MERCHANT_MOE_WMNT_POOL),
            type(uint256).max
        );
        MoeWmntStrategyLib.WMNT.forceApprove(
            address(MoeWmntStrategyLib.MOE_MERCHANT_MOE_WMNT_POOL),
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

    function resetAllowances() external onlyAuthorized {
        _resetAllowances();
    }

    function updateOracle() external onlyAuthorized {
        MoeWmntStrategyLib.updateTraces(address(want), this.update);
    }

    function setOracleWindowSize(
        uint256 newWindowSize
    ) external onlyAuthorized {
        _setWindowSize(newWindowSize);
    }

    function setSlippage(uint256 newSlippage) external onlyAuthorized {
        slippageBps = newSlippage;
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
        return MoeWmntStrategyLib.wantToCircuitShares(amount, address(want));
    }

    function circuitSharesToWant(
        uint256 amount
    ) public view returns (uint256 result) {
        return MoeWmntStrategyLib.circuitSharesToWant(amount, address(want));
    }

    function _withdrawSome(uint256 _amountNeeded) internal {
        if (_amountNeeded == 0) {
            return;
        }

        address wantAddress = address(want);

        uint256 moeBalanceLeft = MoeWmntStrategyLib.MOE.balanceOf(
            address(this)
        );
        uint256 wmntBalanceLeft = MoeWmntStrategyLib.WMNT.balanceOf(
            address(this)
        );

        uint256 moeBalanceLeftInWant = MoeWmntStrategyLib.moeToUsdcQuote(
            wantAddress,
            moeBalanceLeft
        );
        uint256 wmntBalanceLeftInWant = MoeWmntStrategyLib.wmntToUsdcQuote(
            wantAddress,
            wmntBalanceLeft
        );

        uint256 wantAmountFromMoe;
        uint256 wantAmountFromWmnt;
        uint256 wantLeft;

        if (moeBalanceLeftInWant >= _amountNeeded) {
            wantLeft = moeBalanceLeftInWant - _amountNeeded;
            uint256 moeTokensToPreventFromSwap;
            if (wantLeft > 0) {
                moeTokensToPreventFromSwap = MoeWmntStrategyLib.usdcToMoeQuote(
                    wantAddress,
                    wantLeft
                );
            }
            uint256 moeToSwap = moeBalanceLeft - moeTokensToPreventFromSwap;
            wantAmountFromMoe = MoeWmntStrategyLib.moeToUsdcSwap(
                address(want),
                moeToSwap,
                slippageBps,
                this.consult
            );
            emit WithdrawnWithMoe(moeToSwap, wantAmountFromMoe);
        } else if (wmntBalanceLeftInWant >= _amountNeeded) {
            wantLeft = wmntBalanceLeftInWant - _amountNeeded;
            uint256 wmntTokensToPreventFromSwap;
            if (wantLeft > 0) {
                wmntTokensToPreventFromSwap = MoeWmntStrategyLib
                    .usdcToWmntQuote(wantAddress, wantLeft);
            }
            uint256 wmntToSwap = wmntBalanceLeft - wmntTokensToPreventFromSwap;
            wantAmountFromWmnt = MoeWmntStrategyLib.wmntToUsdcSwap(
                wantAddress,
                wmntToSwap,
                slippageBps,
                this.consult
            );
            emit WithdrawnWithWmnt(wmntToSwap, wantAmountFromWmnt);
        } else if (
            moeBalanceLeftInWant + wmntBalanceLeftInWant >= _amountNeeded
        ) {
            wantAmountFromMoe = MoeWmntStrategyLib.moeToUsdcSwap(
                wantAddress,
                moeBalanceLeft,
                slippageBps,
                this.consult
            );
            wantAmountFromWmnt = MoeWmntStrategyLib.wmntToUsdcSwap(
                wantAddress,
                wmntBalanceLeft,
                slippageBps,
                this.consult
            );
            wantLeft =
                (moeBalanceLeftInWant + wmntBalanceLeftInWant) -
                _amountNeeded;
            if (wantLeft > 0) {
                MoeWmntStrategyLib.mintShares(
                    wantLeft,
                    wantAddress,
                    slippageBps,
                    this.consult
                );
            }
            emit WithdrawnWithMoeAndWmnt(
                moeBalanceLeft,
                wmntBalanceLeft,
                wantLeft,
                wantAmountFromMoe,
                wantAmountFromWmnt
            );
        } else {
            wantAmountFromMoe = MoeWmntStrategyLib.moeToUsdcSwap(
                wantAddress,
                moeBalanceLeft,
                slippageBps,
                this.consult
            );
            wantAmountFromWmnt = MoeWmntStrategyLib.wmntToUsdcSwap(
                wantAddress,
                wmntBalanceLeft,
                slippageBps,
                this.consult
            );
            uint256 sharesToWithdraw = Math.min(
                wantToCircuitShares(
                    _amountNeeded - (wantAmountFromMoe + wantAmountFromWmnt)
                ),
                balanceOfCircuitShares()
            );
            MoeWmntStrategyLib.burnShares(
                sharesToWithdraw,
                address(want),
                slippageBps,
                this.consult
            );
            emit WithdrawnWithSharesBurnAndSwaps(
                moeBalanceLeft,
                wmntBalanceLeft,
                sharesToWithdraw,
                wantAmountFromMoe,
                wantAmountFromWmnt
            );
        }
    }

    function estimatedTotalAssets()
        public
        view
        virtual
        override
        returns (uint256 _wants)
    {
        _wants += want.balanceOf(address(this));
        _wants += MoeWmntStrategyLib.moeToUsdcQuote(
            address(want),
            MoeWmntStrategyLib.MOE.balanceOf(address(this))
        );
        _wants += MoeWmntStrategyLib.wmntToUsdcQuote(
            address(want),
            MoeWmntStrategyLib.WMNT.balanceOf(address(this))
        );
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
            MoeWmntStrategyLib.mintShares(
                _excessWant,
                address(want),
                slippageBps,
                this.consult
            );
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        _withdrawSome(balanceOfCircuitShares());
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
            MoeWmntStrategyLib.mintShares(
                wantBalance,
                address(want),
                slippageBps,
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
