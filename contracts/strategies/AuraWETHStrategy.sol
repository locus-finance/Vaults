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
    address internal constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;
    address internal constant AURA_BOOSTER =
        0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
    address internal constant AURA_WETH_REWARDS =
        0x712CC5BeD99aA06fC4D5FB50Aea3750fA5161D0f;
    address internal constant WETH_BAL_BALANCER_POOL =
        0x5c6Ee304399DBdB9C8Ef030aB642B10820DB8F56;

    bytes32 internal constant WETH_3POOL_BALANCER_POOL_ID =
        0x08775ccb6674d6bdceb0797c364c2653ed84f3840002000000000000000004f0;
    bytes32 internal constant STABLE_POOL_BALANCER_POOL_ID =
        0x79c58f70905f734641735bc61e45c19dd9ad60bc0000000000000000000004e7;
    bytes32 internal constant WETH_AURA_BALANCER_POOL_ID =
        0xcfca23ca9ca720b6e98e3eb9b6aa0ffc4a5c08b9000200000000000000000274;
    bytes32 internal constant WETH_BAL_BALANCER_POOL_ID =
        0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014;

    uint32 internal constant TWAP_RANGE_SECS = 1800;
    uint256 public slippage = 9500; // 5%

    constructor(address _vault) BaseStrategy(_vault) {
        want.approve(address(balancerVault), type(uint256).max);
        ERC20(BAL).approve(address(balancerVault), type(uint256).max);
        ERC20(AURA).approve(address(balancerVault), type(uint256).max);
        ERC20(WETH).approve(address(balancerVault), type(uint256).max);
        ERC20(WETH_AURA_BALANCER_POOL).approve(
            address(balancerVault),
            type(uint256).max
        );
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

    function balRewards() public view returns (uint256) {
        return IAuraRewards(AURA_WETH_REWARDS).earned(address(this));
    }

    function balanceOfAuraBpt() public view returns (uint256) {
        return IERC20(AURA_WETH_REWARDS).balanceOf(address(this));
    }

    function auraRewards(uint256 _balRewards) public view returns (uint256) {
        return convertCrvToCvx(_balRewards);
    }

    function auraBptToBpt(uint _amountAuraBpt) public pure returns (uint256) {
        return _amountAuraBpt;
    }

    function auraToWant(uint256 auraTokens) public view returns (uint256) {
        uint scaledAmount = Utils.scaleDecimals(
            auraTokens,
            ERC20(AURA),
            ERC20(address(want))
        );
        console.log("Scaled amount: %s to %s", auraTokens, scaledAmount);
        return
            scaledAmount.mul(getAuraPrice()).div(
                10 ** ERC20(address(want)).decimals()
            );
    }

    function balToWant(uint256 balTokens) public view returns (uint256) {
        uint scaledAmount = Utils.scaleDecimals(
            balTokens,
            ERC20(AURA),
            ERC20(address(want))
        );
        console.log("Scaled amount: %s to %s", balTokens, scaledAmount);
        return
            scaledAmount.mul(getBalPrice()).div(
                10 ** ERC20(address(want)).decimals()
            );
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
        return ethToWant(price);
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
        console.log("Price: %s, ethToWant: %s", price, ethToWant(price));
        return ethToWant(price);
    }

    function getBptPrice() public view returns (uint256 price) {
        address priceOracle = WETH_AURA_BALANCER_POOL;
        IBalancerPriceOracle.OracleAverageQuery[] memory queries;
        queries = new IBalancerPriceOracle.OracleAverageQuery[](1);
        queries[0] = IBalancerPriceOracle.OracleAverageQuery({
            variable: IBalancerPriceOracle.Variable.BPT_PRICE,
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

        if (balanceOfUnstakedBpt() > 0) {
            bool auraSuccess = IAuraDeposit(AURA_BOOSTER).depositAll(
                0, // PID
                true // stake
            );
            require(auraSuccess, "Aura deposit failed");

            console.log(
                "LP Staked with Aura: %s",
                IERC20(AURA_WETH_REWARDS).balanceOf(address(this))
            );
        }
    }

    function sellBalAndAura(uint256 _balAmount, uint256 _auraAmount) public {
        // AURA -> WETH -> 3POOL -> USDC
        _auraAmount = ERC20(AURA).balanceOf(address(this));
        console.log("want before: %s", want.balanceOf(address(this)));

        if (_auraAmount > 0) {
            console.log("Selling %s", _auraAmount);

            IBalancerV2Vault.BatchSwapStep[]
                memory swaps = new IBalancerV2Vault.BatchSwapStep[](3);

            swaps[0] = IBalancerV2Vault.BatchSwapStep({
                poolId: WETH_AURA_BALANCER_POOL_ID,
                assetInIndex: 0,
                assetOutIndex: 1,
                amount: _auraAmount,
                userData: abi.encode(0)
            });

            swaps[1] = IBalancerV2Vault.BatchSwapStep({
                poolId: WETH_3POOL_BALANCER_POOL_ID,
                assetInIndex: 1,
                assetOutIndex: 2,
                amount: 0,
                userData: abi.encode(0)
            });

            swaps[2] = IBalancerV2Vault.BatchSwapStep({
                poolId: STABLE_POOL_BALANCER_POOL_ID,
                assetInIndex: 2,
                assetOutIndex: 3,
                amount: 0,
                userData: abi.encode(0)
            });

            address[] memory assets = new address[](4);
            assets[0] = AURA;
            assets[1] = WETH;
            assets[2] = STABLE_POOL_BALANCER_POOL;
            assets[3] = address(want);

            int[] memory limits = new int[](4);
            limits[0] = int256(_auraAmount);
            limits[3] =
                (-1) *
                int((auraToWant(_auraAmount) * slippage) / 10000);

            console.log("aura to want: %s", auraToWant(_auraAmount));

            balancerVault.batchSwap(
                IBalancerV2Vault.SwapKind.GIVEN_IN,
                swaps,
                assets,
                getFundManagement(),
                limits,
                block.timestamp
            );

            console.log("Got want: %s", want.balanceOf(address(this)));
        }

        _balAmount = ERC20(BAL).balanceOf(address(this));
        if (_balAmount > 0) {
            console.log("Selling BAL %s", _balAmount);

            IBalancerV2Vault.BatchSwapStep[]
                memory swaps = new IBalancerV2Vault.BatchSwapStep[](3);

            swaps[0] = IBalancerV2Vault.BatchSwapStep({
                poolId: WETH_BAL_BALANCER_POOL_ID,
                assetInIndex: 0,
                assetOutIndex: 1,
                amount: _balAmount,
                userData: abi.encode(0)
            });

            swaps[1] = IBalancerV2Vault.BatchSwapStep({
                poolId: WETH_3POOL_BALANCER_POOL_ID,
                assetInIndex: 1,
                assetOutIndex: 2,
                amount: 0,
                userData: abi.encode(0)
            });

            swaps[2] = IBalancerV2Vault.BatchSwapStep({
                poolId: STABLE_POOL_BALANCER_POOL_ID,
                assetInIndex: 2,
                assetOutIndex: 3,
                amount: 0,
                userData: abi.encode(0)
            });

            address[] memory assets = new address[](4);
            assets[0] = BAL;
            assets[1] = WETH;
            assets[2] = STABLE_POOL_BALANCER_POOL;
            assets[3] = address(want);

            int[] memory limits = new int[](4);
            limits[0] = int256(_balAmount);
            limits[3] = (-1) * int((balToWant(_balAmount) * slippage) / 10000);

            console.log("bal to want: %s", balToWant(_balAmount));

            balancerVault.batchSwap(
                IBalancerV2Vault.SwapKind.GIVEN_IN,
                swaps,
                assets,
                getFundManagement(),
                limits,
                block.timestamp
            );

            console.log("Got want: %s", want.balanceOf(address(this)));
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
        IConvexRewards(AURA_WETH_REWARDS).getReward(address(this), true);
        // _sellBalAndAura(
        //     IERC20(BAL).balanceOf(address(this)),
        //     IERC20(AURA).balanceOf(address(this))
        // );
        _exitPosition(IERC20(AURA_WETH_REWARDS).balanceOf(address(this)));
        return want.balanceOf(address(this));
        return want.balanceOf(address(this));
    }

    function _exitPosition(uint256 bptAmount) internal {}

    function prepareMigration(address _newStrategy) internal override {
        IConvexRewards auraPool = IConvexRewards(AURA_WETH_REWARDS);
        auraPool.withdrawAndUnwrap(auraPool.balanceOf(address(this)), true);

        uint256 auraBal = IERC20(AURA).balanceOf(address(this));
        if (auraBal > 0) {
            IERC20(AURA).safeTransfer(_newStrategy, auraBal);
        }
        uint256 balancerBal = IERC20(BAL).balanceOf(address(this));
        if (balancerBal > 0) {
            IERC20(BAL).safeTransfer(_newStrategy, balancerBal);
        }
        uint256 bptBal = IERC20(WETH_AURA_BALANCER_POOL).balanceOf(
            address(this)
        );
        if (bptBal > 0) {
            IERC20(WETH_AURA_BALANCER_POOL).safeTransfer(_newStrategy, bptBal);
        }
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](4);
        protected[0] = AURA_WETH_REWARDS;
        protected[1] = WETH_AURA_BALANCER_POOL;
        protected[2] = BAL;
        protected[3] = AURA;
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

    function convertCrvToCvx(
        uint256 _amount
    ) internal view returns (uint256 amount) {
        address minter = IAuraToken(AURA).minter();
        uint256 inflationProtectionTime = IAuraMinter(minter)
            .inflationProtectionTime();

        if (block.timestamp > inflationProtectionTime) {
            // Inflation protected for now
            return 0;
        }

        uint256 supply = ICvx(AURA).totalSupply();
        uint256 totalCliffs = ICvx(AURA).totalCliffs();
        uint256 maxSupply = ICvx(AURA).EMISSIONS_MAX_SUPPLY();
        uint256 initMintAmount = ICvx(AURA).INIT_MINT_AMOUNT();

        // After AuraMinter.inflationProtectionTime has passed, this calculation might not be valid.
        // uint256 emissionsMinted = supply - initMintAmount - minterMinted;
        uint256 emissionsMinted = supply - initMintAmount;

        uint256 cliff = emissionsMinted.div(ICvx(AURA).reductionPerCliff());

        // e.g. 100 < 500
        if (cliff < totalCliffs) {
            // e.g. (new) reduction = (500 - 100) * 2.5 + 700 = 1700;
            // e.g. (new) reduction = (500 - 250) * 2.5 + 700 = 1325;
            // e.g. (new) reduction = (500 - 400) * 2.5 + 700 = 950;
            uint256 reduction = totalCliffs.sub(cliff).mul(5).div(2).add(700);
            // e.g. (new) amount = 1e19 * 1700 / 500 =  34e18;
            // e.g. (new) amount = 1e19 * 1325 / 500 =  26.5e18;
            // e.g. (new) amount = 1e19 * 950 / 500  =  19e17;
            amount = _amount.mul(reduction).div(totalCliffs);
            // e.g. amtTillMax = 5e25 - 1e25 = 4e25
            uint256 amtTillMax = maxSupply.sub(emissionsMinted);
            if (amount > amtTillMax) {
                amount = amtTillMax;
            }
        }
    }
}
