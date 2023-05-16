// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {BaseStrategy, StrategyParams} from "@yearn-protocol/contracts/BaseStrategy.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../integrations/balancer/IBalancerV2Vault.sol";
import "../integrations/balancer/IBalancerPool.sol";
import "../integrations/balancer/IBalancerPriceOracle.sol";
import "../integrations/aura/IAuraBooster.sol";
import "../integrations/aura/IAuraDeposit.sol";
import "../integrations/aura/IAuraRewards.sol";
import "../integrations/aura/IConvexRewards.sol";
import "../integrations/aura/ICvx.sol";
import "../integrations/aura/IAuraToken.sol";
import "../integrations/aura/IAuraMinter.sol";

import "../utils/AuraMath.sol";
import "../utils/Utils.sol";

import "hardhat/console.sol";

contract AuraWETHStrategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using AuraMath for uint256;

    IBalancerV2Vault internal constant balancerVault =
        IBalancerV2Vault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    address internal constant USDC_WETH_BALANCER_POOL =
        0x96646936b91d6B9D7D0c47C496AfBF3D6ec7B6f8;
    address internal constant STABLE_POOL_BALANCER_POOL =
        0x79c58f70905F734641735BC61e45c19dD9Ad60bC;
    address internal constant WETH_AURA_BALANCER_POOL =
        0xCfCA23cA9CA720B6E98E3Eb9B6aa0fFC4a5C08B9;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant AURA = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;

    bytes32 internal constant WETH_3POOL_BALANCER_POOL_ID =
        0x08775ccb6674d6bdceb0797c364c2653ed84f3840002000000000000000004f0;
    bytes32 internal constant STABLE_POOL_BALANCER_POOL_ID =
        0x79c58f70905f734641735bc61e45c19dd9ad60bc0000000000000000000004e7;
    bytes32 internal constant WETH_AURA_BALANCER_POOL_ID =
        0xcfca23ca9ca720b6e98e3eb9b6aa0ffc4a5c08b9000200000000000000000274;

    uint32 internal constant TWAP_RANGE_SECS = 1800;
    uint256 public slippage = 9500; // 5%

    constructor(address _vault) BaseStrategy(_vault) {
        want.approve(address(balancerVault), type(uint256).max);
        ERC20(AURA).approve(address(balancerVault), type(uint256).max);
        ERC20(WETH).approve(address(balancerVault), type(uint256).max);
    }

    function name() external pure override returns (string memory) {
        return "StrategyAuraWETH";
    }

    /// @notice Balance of want sitting in our strategy.
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfUnstakedBpt() public view returns (uint256) {
        return IERC20(WETH_AURA_BALANCER_POOL).balanceOf(address(this));
    }

    function estimatedTotalAssets()
        public
        view
        override
        returns (uint256 _wants)
    {}

    function getBalPrice() public view returns (uint256 price) {
        address priceOracle = 0x5c6Ee304399DBdB9C8Ef030aB642B10820DB8F56;
        IBalancerPriceOracle.OracleAverageQuery[] memory queries;
        queries = new IBalancerPriceOracle.OracleAverageQuery[](1);
        queries[0] = IBalancerPriceOracle.OracleAverageQuery({
            variable: IBalancerPriceOracle.Variable.PAIR_PRICE,
            secs: 1800,
            ago: 0
        });
        uint256[] memory results = IBalancerPriceOracle(priceOracle)
            .getTimeWeightedAverage(queries);
        price = 1e36 / results[0];
    }

    function getAuraPrice() public view returns (uint256 price) {
        address priceOracle = 0xc29562b045D80fD77c69Bec09541F5c16fe20d9d;
        IBalancerPriceOracle.OracleAverageQuery[] memory queries;
        queries = new IBalancerPriceOracle.OracleAverageQuery[](1);
        queries[0] = IBalancerPriceOracle.OracleAverageQuery({
            variable: IBalancerPriceOracle.Variable.PAIR_PRICE,
            secs: 1800,
            ago: 0
        });
        uint256[] memory results;
        results = IBalancerPriceOracle(priceOracle).getTimeWeightedAverage(
            queries
        );
        price = results[0];
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
        uint256 _wantBal = want.balanceOf(address(this));
        if (_wantBal > _debtOutstanding) {
            uint256 _excessWant = _wantBal - _debtOutstanding;
        }
    }

    function buyTokens() external {
        uint256 _wantBal = want.balanceOf(address(this));

        if (_wantBal > 0) {
            IBalancerV2Vault.BatchSwapStep[]
                memory swaps = new IBalancerV2Vault.BatchSwapStep[](2);

            swaps[0] = IBalancerV2Vault.BatchSwapStep({
                poolId: STABLE_POOL_BALANCER_POOL_ID,
                assetInIndex: 0,
                assetOutIndex: 1,
                amount: _wantBal,
                userData: abi.encode(0)
            });

            swaps[1] = IBalancerV2Vault.BatchSwapStep({
                poolId: WETH_3POOL_BALANCER_POOL_ID,
                assetInIndex: 1,
                assetOutIndex: 2,
                amount: 0,
                userData: abi.encode(0)
            });

            address[] memory assets = new address[](3);
            assets[0] = address(want);
            assets[1] = STABLE_POOL_BALANCER_POOL;
            assets[2] = WETH;

            int[] memory limits = new int[](3);
            limits[0] = int(_wantBal);
            limits[1] = 0;
            limits[2] = 0;

            balancerVault.batchSwap(
                IBalancerV2Vault.SwapKind.GIVEN_IN,
                swaps,
                assets,
                getFundManagement(),
                limits,
                block.timestamp
            );
        }

        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));

        if (wethBalance > 0) {
            console.log("Got WETH: %s", wethBalance);

            uint256[] memory _amountsIn = new uint256[](2);
            _amountsIn[0] = wethBalance;
            _amountsIn[1] = 0;

            address[] memory _assets = new address[](2);
            _assets[0] = WETH;
            _assets[1] = AURA;

            uint256[] memory _maxAmountsIn = new uint256[](2);
            _maxAmountsIn[0] = wethBalance;
            _maxAmountsIn[1] = 0;

            bytes memory _userData = abi.encode(
                IBalancerV2Vault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                _amountsIn,
                0
            );

            IBalancerV2Vault.JoinPoolRequest memory _request;
            _request = IBalancerV2Vault.JoinPoolRequest({
                assets: _assets,
                maxAmountsIn: _maxAmountsIn,
                userData: _userData,
                fromInternalBalance: false
            });

            balancerVault.joinPool({
                poolId: WETH_AURA_BALANCER_POOL_ID,
                sender: address(this),
                recipient: payable(address(this)),
                request: _request
            });

            console.log("Got LP", balanceOfUnstakedBpt());
        }
    }

    function withdrawSome(uint256 _amountNeeded) internal {}

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
        return want.balanceOf(address(this));
    }

    function _exitPosition(uint256 bptAmount) internal {}

    function prepareMigration(address _newStrategy) internal override {}

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](0);
        return protected;
    }

    function ethToWant(
        uint256 _amtInWei
    ) public view override returns (uint256) {
        IBalancerPriceOracle.OracleAverageQuery[] memory queries;
        queries = new IBalancerPriceOracle.OracleAverageQuery[](1);
        queries[0] = IBalancerPriceOracle.OracleAverageQuery({
            variable: IBalancerPriceOracle.Variable.PAIR_PRICE,
            secs: TWAP_RANGE_SECS,
            ago: 0
        });

        uint256[] memory results;
        results = IBalancerPriceOracle(USDC_WETH_BALANCER_POOL)
            .getTimeWeightedAverage(queries);

        return
            Utils.scaleDecimals(
                (_amtInWei * results[0]) / 1e18,
                ERC20(WETH),
                ERC20(address(want))
            );
    }

    function getFundManagement()
        internal
        view
        returns (IBalancerV2Vault.FundManagement memory fundManagement)
    {
        fundManagement = IBalancerV2Vault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });
    }
}
