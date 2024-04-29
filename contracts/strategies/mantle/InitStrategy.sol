// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../abstracts/BaseStrategyForSeparatedVault.sol";

import "../../integrations/init/IInitCore.sol";
import "../../integrations/init/IIRM.sol";
import "../../integrations/init/ILendingPool.sol";
import "../../utils/Utils.sol";

contract InitStrategy is BaseStrategyForSeparatedVault {
    using SafeERC20 for IERC20;
    using Math for uint256;

    event MintedOrBurnedShares(uint256 indexed shares, bool indexed isMint);

    struct PreviewAccrueInterestData {
        uint256 totalAssets;
        uint256 totalShares;
    }

    IInitCore public constant INIT_CORE =
        IInitCore(0x972BcB0284cca0152527c4f70f8F689852bCAFc5);
    ILendingPool public constant INIT_USDC_LENDING_POOL =
        ILendingPool(0x00A55649E597d463fD212fBE48a3B40f0E227d06);

    uint8 public constant VIRTUAL_SHARE_DECIMALS = 8;
    uint256 public constant ONE_E18 = 1e18;
    uint256 public constant VIRTUAL_SHARES = 10 ** VIRTUAL_SHARE_DECIMALS;
    uint256 public constant VIRTUAL_ASSETS = 1;

    IIRM public irm;

    function initialize(address _vault, address _strategist) external {
        __Base_Strategy_Initialize(
            _vault,
            _strategist,
            _strategist,
            _strategist
        );
        irm = IIRM(INIT_USDC_LENDING_POOL.irm());
        want.approve(address(INIT_USDC_LENDING_POOL), type(uint256).max);
        IERC20(address(INIT_USDC_LENDING_POOL)).approve(
            address(INIT_USDC_LENDING_POOL),
            type(uint256).max
        );
    }

    function name() external pure override returns (string memory) {
        return "InitStrategy USDC";
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfShares() public view returns (uint256) {
        return IERC20(address(INIT_USDC_LENDING_POOL)).balanceOf(address(this));
    }

    function _wantToShares(uint256 amount) internal returns (uint256) {
        return INIT_USDC_LENDING_POOL.toSharesCurrent(amount);
    }

    function _withdrawSome(uint256 _amountNeeded) internal {
        if (_amountNeeded == 0) {
            return;
        }
        uint256 sharesToWithdraw = Math.min(
            _wantToShares(_amountNeeded),
            balanceOfShares()
        );
        _exitPosition(sharesToWithdraw);
    }

    function getShares(
        uint _amt,
        uint _totalAssets,
        uint _totalShares
    ) public pure returns (uint shares) {
        return
            _amt.mulDiv(
                _totalShares + VIRTUAL_SHARES,
                _totalAssets + VIRTUAL_ASSETS
            );
    }

    function getWant(
        uint _shares,
        uint _totalAssets,
        uint _totalShares
    ) public pure returns (uint amt) {
        return
            _shares.mulDiv(
                _totalAssets + VIRTUAL_ASSETS,
                _totalShares + VIRTUAL_SHARES
            );
    }

    /// @dev Imitates accrueInterest() in the ILendingPool to adjust total supply hence taking into account an interest in want tokens.
    function previewAccrueInterest()
        public
        view
        returns (PreviewAccrueInterestData memory result)
    {
        result = PreviewAccrueInterestData({
            totalAssets: INIT_USDC_LENDING_POOL.totalAssets(),
            totalShares: IERC20(address(INIT_USDC_LENDING_POOL)).totalSupply()
        });
        uint256 _lastAccruedTime = INIT_USDC_LENDING_POOL.lastAccruedTime();
        uint256 _totalDebt = INIT_USDC_LENDING_POOL.totalDebt();
        uint256 _cash = INIT_USDC_LENDING_POOL.cash();
        uint256 borrowRate_e18 = IIRM(irm).getBorrowRate_e18(_cash, _totalDebt);
        uint256 accruedInterest = (borrowRate_e18 *
            (block.timestamp - _lastAccruedTime) *
            _totalDebt) / ONE_E18;
        uint256 reserve = (accruedInterest *
            INIT_USDC_LENDING_POOL.reserveFactor_e18()) / ONE_E18;
        if (reserve > 0) {
            result.totalShares += getShares(
                reserve,
                _cash + _totalDebt + accruedInterest - reserve,
                result.totalShares
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
        PreviewAccrueInterestData memory data = previewAccrueInterest();
        _wants += getWant(
            balanceOfShares(),
            data.totalAssets,
            data.totalShares
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
            _mintShares(_excessWant);
        }
    }

    function _exitPosition(uint256 _shares) internal {
        _burnShares(_shares);
    }

    function _mintShares(uint256 _amount) internal {
        want.safeTransfer(address(INIT_USDC_LENDING_POOL), _amount);
        uint256 sharesMinted = INIT_CORE.mintTo(
            address(INIT_USDC_LENDING_POOL),
            address(this)
        );
        emit MintedOrBurnedShares(sharesMinted, true);
    }

    function _burnShares(uint256 _shares) internal {
        IERC20(address(INIT_USDC_LENDING_POOL)).safeTransfer(
            address(INIT_USDC_LENDING_POOL),
            _shares
        );
        INIT_CORE.burnTo(address(INIT_USDC_LENDING_POOL), address(this));
        emit MintedOrBurnedShares(_shares, false);
    }

    function liquidateAllPositions() internal override returns (uint256) {
        _exitPosition(balanceOfShares());
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
            _mintShares(wantBalance);
        }
        IERC20(address(INIT_USDC_LENDING_POOL)).safeTransfer(
            _newStrategy,
            balanceOfShares()
        );
    }

    function protectedTokens()
        internal
        pure
        override
        returns (address[] memory protected)
    {}

    receive() external payable {}
    
    function advicePerformanceFee(
        uint256 performanceFeeFromVault
    )
        external
        pure
        virtual
        override
        returns (uint256 correctedPerformanceFee)
    {
        return performanceFeeFromVault;
    }
}
