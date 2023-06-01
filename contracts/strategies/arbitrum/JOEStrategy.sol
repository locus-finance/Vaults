// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {BaseStrategy, StrategyParams, VaultAPI} from "@yearn-protocol/contracts/BaseStrategy.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

import "../../utils/Utils.sol";
import "../../integrations/chainlink/AggregatorV3Interface.sol";
import "../../integrations/joe/IStableJoeStaking.sol";
import "../../integrations/joe/ILBRouter.sol";

contract JOEStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    address internal constant JOE = 0x371c7ec6D8039ff7933a2AA28EB827Ffe1F52f07;
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    address internal constant ETH_USDC_UNI_V3_POOL =
        0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443;
    address internal constant JOE_USD_CHAINLINK_FEED =
        0x04180965a782E487d0632013ABa488A472243542;
    address internal constant JOE_LB_ROUTER =
        0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30;
    address internal constant STABLE_JOE_STAKING =
        0x43646A8e839B2f2766392C1BF8f60F6e587B6960;

    // As of moment of writing, this is the only reward token for staking JOE.
    // It is the same as the want token of this strategy (USDC).
    // We also support reward token to be JOE as this could happen in the future.
    // Strategist can set this to JOE if we want to claim JOE rewards.
    address public JOE_REWARD_TOKEN =
        0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    uint32 internal constant TWAP_RANGE_SECS = 1800;
    uint256 public slippage = 9500; // 5%

    constructor(address _vault) BaseStrategy(_vault) {
        ERC20(JOE).approve(STABLE_JOE_STAKING, type(uint256).max);
        ERC20(JOE).approve(JOE_LB_ROUTER, type(uint256).max);

        want.approve(JOE_LB_ROUTER, type(uint256).max);
    }

    function setRewardToken(address _rewardToken) external onlyStrategist {
        require(
            _rewardToken == JOE || _rewardToken == address(want),
            "!_rewardToken"
        );
        JOE_REWARD_TOKEN = _rewardToken;
    }

    function setSlippage(uint256 _slippage) external onlyStrategist {
        require(_slippage < 10_000, "!_slippage");
        slippage = _slippage;
    }

    function name() external pure override returns (string memory) {
        return "StrategyJOE";
    }

    function balanceOfUnstakedJoe() public view returns (uint256) {
        return ERC20(JOE).balanceOf(address(this));
    }

    function balanceOfStakedJoe() public view returns (uint256) {
        (uint256 amount, ) = IStableJoeStaking(STABLE_JOE_STAKING).getUserInfo(
            address(this),
            address(0)
        );
        return amount;
    }

    function balanceOfRewards() public view virtual returns (uint256) {
        uint256 rewards = IStableJoeStaking(STABLE_JOE_STAKING).pendingReward(
            address(this),
            JOE_REWARD_TOKEN
        );
        return rewards;
    }

    function rewardsToWant(uint256 rewards) public view returns (uint256) {
        if (JOE_REWARD_TOKEN == address(want)) {
            return rewards;
        } else {
            return joeToWant(rewards);
        }
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function _claimAndSellRewards() internal {
        uint256 rewards = balanceOfRewards();
        IStableJoeStaking(STABLE_JOE_STAKING).withdraw(0);

        if (JOE_REWARD_TOKEN == JOE) {
            _sellJoeForWant(rewards);
        }
    }

    function _withdrawSome(uint256 _amountNeeded) internal {
        if (_amountNeeded == 0) {
            return;
        }

        uint256 totalRewards = rewardsToWant(balanceOfRewards());

        if (totalRewards >= _amountNeeded) {
            _claimAndSellRewards();
        } else {
            uint256 _joeToUnstake = Math.min(
                balanceOfStakedJoe(),
                wantToJoe(_amountNeeded - totalRewards)
            );
            _exitPosition(_joeToUnstake);
        }
    }

    function _exitPosition(uint256 _stakedJoeAmount) internal {
        if (_stakedJoeAmount > 0) {
            IStableJoeStaking(STABLE_JOE_STAKING).withdraw(_stakedJoeAmount);
            _sellJoeForWant(balanceOfUnstakedJoe());
        }
    }

    function _sellJoeForWant(uint256 _joeAmount) internal {
        if (_joeAmount > 0) {
            uint256 wantExpected = joeToWant(_joeAmount);

            IERC20[] memory tokenPath = new IERC20[](3);
            tokenPath[0] = IERC20(JOE);
            tokenPath[1] = IERC20(WETH);
            tokenPath[2] = want;

            uint256[] memory pairBinSteps = new uint256[](2);
            pairBinSteps[0] = 20;
            pairBinSteps[1] = 15;

            ILBRouter.Version[] memory versions = new ILBRouter.Version[](2);
            versions[0] = ILBRouter.Version.V2_1;
            versions[1] = ILBRouter.Version.V2_1;

            ILBRouter.Path memory path;
            path.pairBinSteps = pairBinSteps;
            path.versions = versions;
            path.tokenPath = tokenPath;

            ILBRouter(JOE_LB_ROUTER).swapExactTokensForTokens(
                _joeAmount,
                (wantExpected * slippage) / 10000,
                path,
                address(this),
                block.timestamp
            );
        }
    }

    function ethToWant(
        uint256 _amtInWei
    ) public view override returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            ETH_USDC_UNI_V3_POOL,
            TWAP_RANGE_SECS
        );
        return
            OracleLibrary.getQuoteAtTick(
                meanTick,
                uint128(_amtInWei),
                WETH,
                address(want)
            );
    }

    function estimatedTotalAssets()
        public
        view
        virtual
        override
        returns (uint256 _wants)
    {
        _wants = balanceOfWant();
        _wants += joeToWant(balanceOfStakedJoe() + balanceOfUnstakedJoe());
        _wants += rewardsToWant(balanceOfRewards());
    }

    function joeToWant(uint256 _joeAmount) public view returns (uint256) {
        (, int256 price, , , ) = AggregatorV3Interface(JOE_USD_CHAINLINK_FEED)
            .latestRoundData();
        uint8 chainlinkDecimals = AggregatorV3Interface(JOE_USD_CHAINLINK_FEED)
            .decimals();
        uint256 priceScaled = uint256(price) * (10 ** (18 - chainlinkDecimals));

        return
            Utils.scaleDecimals(
                (priceScaled * _joeAmount) / 1 ether,
                ERC20(JOE),
                ERC20(address(want))
            );
    }

    function wantToJoe(
        uint256 _wantAmount
    ) public view virtual returns (uint256) {
        uint256 joeExpectedUnscaled = (_wantAmount *
            (10 ** ERC20(address(want)).decimals())) / joeToWant(1 ether);
        return
            Utils.scaleDecimals(
                joeExpectedUnscaled,
                ERC20(address(want)),
                ERC20(JOE)
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
        uint256 _totalDebt = vault.strategies(address(this)).totalDebt;

        if (_totalAssets >= _totalDebt) {
            _profit = _totalAssets - _totalDebt;
            _loss = 0;
        } else {
            _profit = 0;
            _loss = _totalDebt - _totalAssets;
        }

        _withdrawSome(_debtOutstanding + _profit);

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

        _claimAndSellRewards();

        if (_wantBal > _debtOutstanding) {
            uint256 _excessWant = _wantBal - _debtOutstanding;

            uint256 joeExpected = wantToJoe(_excessWant);

            IERC20[] memory tokenPath = new IERC20[](3);
            tokenPath[0] = want;
            tokenPath[1] = IERC20(WETH);
            tokenPath[2] = IERC20(JOE);

            uint256[] memory pairBinSteps = new uint256[](2);
            pairBinSteps[0] = 15;
            pairBinSteps[1] = 20;

            ILBRouter.Version[] memory versions = new ILBRouter.Version[](2);
            versions[0] = ILBRouter.Version.V2_1;
            versions[1] = ILBRouter.Version.V2_1;

            ILBRouter.Path memory path;
            path.pairBinSteps = pairBinSteps;
            path.versions = versions;
            path.tokenPath = tokenPath;

            ILBRouter(JOE_LB_ROUTER).swapExactTokensForTokens(
                _excessWant,
                (joeExpected * slippage) / 10000,
                path,
                address(this),
                block.timestamp
            );
        }

        if (balanceOfUnstakedJoe() > 0) {
            IStableJoeStaking(STABLE_JOE_STAKING).deposit(
                balanceOfUnstakedJoe()
            );
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        _exitPosition(balanceOfStakedJoe());
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
        IStableJoeStaking(STABLE_JOE_STAKING).withdraw(balanceOfStakedJoe());
        IERC20(JOE).transfer(_newStrategy, balanceOfUnstakedJoe());
    }

    function protectedTokens()
        internal
        pure
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](1);
        protected[0] = JOE;
        return protected;
    }
}
