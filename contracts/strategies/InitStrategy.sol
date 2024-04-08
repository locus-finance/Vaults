// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {BaseStrategy} from "@yearn-protocol/contracts/BaseStrategy.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../integrations/fusionx/ISwapRouter.sol";
import "../integrations/init/IMoneyMarketHook.sol";
import "../integrations/init/IInitCore.sol";
import "../integrations/init/IIRM.sol";
import "../integrations/init/ILendingPool.sol";
import "../utils/Utils.sol";

contract InitStrategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;

    struct PreviewAccrueInterestData {
        uint256 totalAssets;
        uint256 totalShares;
    }

    ISwapRouter public constant FUSIONX_SWAP_ROUTER =
        ISwapRouter(0x5989FB161568b9F133eDf5Cf6787f5597762797F);
    IMoneyMarketHook public constant MONEY_MARKET_HOOK =
        IMoneyMarketHook(0xf82CBcAB75C1138a8F1F20179613e7C0C8337346);
    IInitCore public constant INIT_CORE =
        IInitCore(0x972BcB0284cca0152527c4f70f8F689852bCAFc5);
    ILendingPool public constant INIT_USDC_LENDING_POOL =
        ILendingPool(0x00A55649E597d463fD212fBE48a3B40f0E227d06);

    uint16 public constant POSITION_MODE = 1;
    address public constant USDC_ADDRESS =
        0x09Bc4E0D864854c6aFB6eB9A9cdF58aC190D0dF9;
    address public constant WRAPPED_MANTLE = 0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8;
    address public constant USDC_MANTLE_FUSIONX_POOL = 0xe87e42ff34d6baaf619eb91dd957e4ec45226894;

    uint32 internal constant TWAP_RANGE_SECS = 1800;
    uint8 public constant VIRTUAL_SHARE_DECIMALS = 8;
    uint256 public constant ONE_E18 = 1e18;
    uint256 public constant VIRTUAL_SHARES = 10 ** VIRTUAL_SHARE_DECIMALS;
    uint256 public constant VIRTUAL_ASSETS = 1;

    IIRM public irm;
    uint256 public positionId;
    uint256 public initPositionId;
    uint256 public lastMinHealth_e18;

    bytes[] public lastMulticallResults;

    constructor(address _vault) BaseStrategy(_vault) {}

    function initialize(address _vault, address _strategist) external {
        _initialize(_vault, _strategist, _strategist, _strategist);
        irm = IIRM(INIT_USDC_LENDING_POOL.irm());
        want.approve(address(MONEY_MARKET_HOOK), type(uint256).max);
        want.approve(address(INIT_USDC_LENDING_POOL), type(uint256).max);
        IERC20(address(INIT_USDC_LENDING_POOL)).approve(
            address(INIT_USDC_LENDING_POOL),
            type(uint256).max
        );
        IERC20(address(INIT_USDC_LENDING_POOL)).approve(
            address(MONEY_MARKET_HOOK),
            type(uint256).max
        );
    }

    function calculateAndGetCurrentHealthE18() external returns (uint256) {
        return INIT_CORE.getPosHealthCurrent_e18(initPositionId);
    }

    function setMinHealthE18(
        uint256 newLastMinHealth_e18
    ) external onlyStrategist {
        lastMinHealth_e18 = newLastMinHealth_e18;
    }

    function ethToWant(uint256) public view virtual override returns (uint256) {
        return 0;
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

    function _toShares(
        uint _amt,
        uint _totalAssets,
        uint _totalShares
    ) internal pure returns (uint shares) {
        return
            _amt.mulDiv(
                _totalShares + VIRTUAL_SHARES,
                _totalAssets + VIRTUAL_ASSETS
            );
    }

    function _toAmt(
        uint _shares,
        uint _totalAssets,
        uint _totalShares
    ) internal pure returns (uint amt) {
        return
            _shares.mulDiv(
                _totalAssets + VIRTUAL_ASSETS,
                _totalShares + VIRTUAL_SHARES
            );
    }

    function _calcNativeBalanceToUSDC() internal view returns (uint256) {
        uint256 selfBalance = address(this).balance;
        (int24 meanTick, ) = OracleLibrary.consult(USDC_MANTLE_FUSIONX_POOL, TWAP_RANGE_SECS);
        return
            OracleLibrary.getQuoteAtTick(
                meanTick,
                uint128(selfBalance),
                WRAPPED_MANTLE,
                USDC_ADDRESS
            );
    }

    /// @dev Imitates accrueInterest() in the ILendingPool to adjust total supply hence taking into account an interest in want tokens.
    function _previewAccrueInterest()
        internal
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
            result.totalShares += _toShares(
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
        PreviewAccrueInterestData memory data = _previewAccrueInterest();
        _wants += _toAmt(balanceOfShares(), data.totalAssets, data.totalShares);
        _wants += _calcNativeBalanceToUSDC();
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

    function _mintShares(uint256 _amount) internal {
        IMoneyMarketHook.DepositParams[]
            memory depositParams = new IMoneyMarketHook.DepositParams[](1);
        depositParams[0] = IMoneyMarketHook.DepositParams({
            pool: address(INIT_USDC_LENDING_POOL),
            amt: _amount,
            rebaseHelperParams: IMoneyMarketHook.RebaseHelperParams({
                helper: address(0),
                tokenIn: USDC_ADDRESS
            })
        });
        IMoneyMarketHook.WithdrawParams[] memory withdrawParams;
        IMoneyMarketHook.BorrowParams[] memory borrowParams;
        IMoneyMarketHook.RepayParams[] memory repayParams;
        (positionId, initPositionId, lastMulticallResults) = MONEY_MARKET_HOOK
            .execute(
                IMoneyMarketHook.OperationParams({
                    posId: positionId,
                    viewer: address(this),
                    mode: POSITION_MODE,
                    depositParams: depositParams,
                    withdrawParams: withdrawParams,
                    borrowParams: borrowParams,
                    repayParams: repayParams,
                    minHealth_e18: lastMinHealth_e18,
                    returnNative: true
                })
            );
    }

    function _burnShares(uint256 _shares) internal {
        IMoneyMarketHook.DepositParams[] memory depositParams;
        IMoneyMarketHook.WithdrawParams[]
            memory withdrawParams = new IMoneyMarketHook.WithdrawParams[](1);
        withdrawParams[0] = IMoneyMarketHook.WithdrawParams({
            pool: address(INIT_USDC_LENDING_POOL),
            shares: _shares,
            to: address(this),
            rebaseHelperParams: IMoneyMarketHook.RebaseHelperParams({
                helper: address(0),
                tokenIn: USDC_ADDRESS
            })
        });
        IMoneyMarketHook.BorrowParams[] memory borrowParams;
        IMoneyMarketHook.RepayParams[] memory repayParams;
        (positionId, initPositionId, lastMulticallResults) = MONEY_MARKET_HOOK
            .execute(
                IMoneyMarketHook.OperationParams({
                    posId: positionId,
                    viewer: address(this),
                    mode: POSITION_MODE,
                    depositParams: depositParams,
                    withdrawParams: withdrawParams,
                    borrowParams: borrowParams,
                    repayParams: repayParams,
                    minHealth_e18: lastMinHealth_e18,
                    returnNative: true
                })
            );
    }

    function _exitPosition(uint256 _shares) internal {
        _burnShares(_shares);
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
}
