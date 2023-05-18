// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;
pragma experimental ABIEncoderV2;

import {BaseStrategy, StrategyParams} from "@yearn-protocol/contracts/BaseStrategy.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "hardhat/console.sol";

import "../interfaces/IWETH.sol";
import "../integrations/frax/IFraxMinter.sol";
import "../integrations/frax/ISfrxEth.sol";
import "../integrations/curve/ICurve.sol";

contract FraxStrategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;

    address internal constant fraxMinter =
        0xbAFA44EFE7901E04E39Dad13167D089C559c1138;

    address internal constant sfrxEth =
        0xac3E018457B222d93114458476f3E3416Abbe38F;

    address internal constant frxEth =
        0x5E8422345238F34275888049021821E8E08CAa1f;

    address internal constant frxEthCurvePool = 
        0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;

    constructor(address _vault) BaseStrategy(_vault) {
    }

    function name() external view override returns (string memory) {
        return "StrategyFrax";
    }

    /// @notice Balance of want sitting in our strategy.
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function estimatedTotalAssets()
        public
        view
        override
        returns (uint256 _wants)
    {
        console.log("balanceOfWant():\t", balanceOfWant());
        console.log("address(this).balance:\t", address(this).balance);
        console.log("sfrxToWant:\t\t", sfrxToWant(IERC20(sfrxEth).balanceOf(address(this))));
        console.log("frxToWant:\t\t", frxToWant(IERC20(frxEth).balanceOf(address(this))));
        console.log("\n");

        _wants = balanceOfWant();
        _wants += address(this).balance;
        _wants += sfrxToWant(IERC20(sfrxEth).balanceOf(address(this)));
        _wants += frxToWant(IERC20(frxEth).balanceOf(address(this)));
        return _wants;
    }

    function sfrxToWant(uint256 _amount) public view returns (uint256) {
        return frxToWant(ISfrxEth(sfrxEth).previewRedeem(_amount));
    }

    function frxToWant(uint256 _amount) public view returns (uint256) {
        return (ICurve(frxEthCurvePool).price_oracle() * _amount) / 1e18;
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

        withdrawSome(_debtOutstanding + _profit);

        uint256 _liquidWant = want.balanceOf(address(this));

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
        uint256 _wethBal = want.balanceOf(address(this));
        if (_wethBal > _debtOutstanding) {
            uint256 _excessWeth = _wethBal - _debtOutstanding;
            IWETH(address(want)).withdraw(_excessWeth);
            IFraxMinter(fraxMinter).submitAndDeposit{value: address(this).balance}(address(this));
        }
    }

    function withdrawSome(uint256 _amountNeeded) internal {
        console.log("Need to withdrawSome:", _amountNeeded);
        // ISfrxEth(sfrxEth).withdraw(_amountNeeded, address(this), address(this));
    }

    function liquidatePosition(
        uint256 _amountNeeded
    ) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {
        uint256 _wethBal = want.balanceOf(address(this));
        if (_wethBal >= _amountNeeded) {
            return (_amountNeeded, 0);
        }

        withdrawSome(_amountNeeded);

        _wethBal = want.balanceOf(address(this));
        if (_amountNeeded > _wethBal) {
            _liquidatedAmount = _wethBal;
            _loss = _amountNeeded - _wethBal;
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        ISfrxEth(sfrxEth).redeem(
            IERC20(sfrxEth).balanceOf(address(this)), 
            address(this), 
            address(this)
        );
        return want.balanceOf(address(this));
    }

    function prepareMigration(address _newStrategy) internal override {
        uint256 sfrxBal = IERC20(sfrxEth).balanceOf(address(this));
        if (sfrxBal > 0) {
            IERC20(sfrxEth).safeTransfer(_newStrategy, sfrxBal);
        }
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](1);
        protected[0] = sfrxEth;
        return protected;
    }

    function ethToWant(
        uint256 _amtInWei
    ) public view virtual override returns (uint256) {
        return _amtInWei;
    }

    receive() external payable {}
}
