// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {BaseStrategy, StrategyParams, VaultAPI} from "@yearn-protocol/contracts/BaseStrategy.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "../utils/Utils.sol";
import "../integrations/locusPendle/ILocusVaultPendle.sol";

contract LocusPendleVaultStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    ILocusVaultPendle public constant LOCUS_VAULT_PENDLE = ILocusVaultPendle(address(0));
    IVaultToken public constant LOCUS_VAULT_PENDLE_TOKEN = IVaultToken(address(0));

    uint256 public constant PRECISION = 1 ether;

    constructor(address _vault) BaseStrategy(_vault) {}

    function initialize(address _vault, address _strategist) external {
        _initialize(_vault, _strategist, _strategist, _strategist);

        want.forceApprove(address(LOCUS_VAULT_PENDLE), type(uint256).max);
        LOCUS_VAULT_PENDLE_TOKEN.forceApprove(address(LOCUS_VAULT_PENDLE), type(uint256).max);
    }

    function ethToWant(
        uint256 _amtInWei
    ) public view virtual override returns (uint256) {
        return 0;
    }

    function name() external pure override returns (string memory) {
        return "Locus Pendle Vault Strategy";
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfLocusPendleVaultShares() public view returns (uint256) {
        return LOCUS_VAULT_PENDLE_TOKEN.balanceOf(address(this));
    }

    function toLocusPendleVaultShares(uint256 wantAmount) public view returns (uint256 locusPendleVaultShares) {
        locusPendleVaultShares = (wantAmount * PRECISION) / LOCUS_VAULT_PENDLE.pricePerShare();
    }

    function fromLocusPendleVaultShares(uint256 locusPendleVaultShares) public view returns (uint256 wantAmount) {
        wantAmount = (locusPendleVaultShares * LOCUS_VAULT_PENDLE.pricePerShare()) / PRECISION;
    }


    function estimatedTotalAssets()
        public
        view
        virtual
        override
        returns (uint256 _wants)
    {
        _wants += want.balanceOf(address(this));
        _wants += fromLocusPendleVaultShares(balanceOfLocusPendleVaultShares());
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
            LOCUS_VAULT_PENDLE.deposit(_excessWant);
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        _withdrawSome(balanceOfLocusPendleVaultShares());
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
        LOCUS_VAULT_PENDLE_TOKEN.safeTransfer(
            _newStrategy,
            LOCUS_VAULT_PENDLE_TOKEN.balanceOf(address(this))
        );
    }

    function protectedTokens()
        internal
        pure
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](1);
        protected[0] = address(LOCUS_VAULT_PENDLE_TOKEN);
        return protected;
    }

    function _withdrawSome(uint256 _amountNeeded) internal {
        if (_amountNeeded == 0) {
            return;
        }
        uint256 sharesToWithdraw = Math.min(
            toLocusPendleVaultShares(_amountNeeded),
            balanceOfLocusPendleVaultShares()
        );
        LOCUS_VAULT_PENDLE.withdraw(sharesToWithdraw);
    }

    receive() external payable {}
}
