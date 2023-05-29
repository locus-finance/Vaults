// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {BaseStrategy, StrategyParams, VaultAPI} from "@yearn-protocol/contracts/BaseStrategy.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

import "../../integrations/gmx/IRewardRouterV2.sol";
import "../../integrations/gmx/IRewardTracker.sol";

import "hardhat/console.sol";

contract GMXStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    address internal constant ETH_USDC_UNI_V3_POOL =
        0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443;
    address internal constant ETH_GMX_UNI_V3_POOL =
        0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;
    address internal constant STAKED_GMX_TRACKER =
        0x908C4D94D34924765f1eDc22A1DD098397c59dD4;
    address internal constant FEE_GMX_TRACKER =
        0xd2D1162512F927a7e282Ef43a362659E4F2a728F;

    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address internal constant GMX = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;
    address internal constant ES_GMX =
        0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA;

    address internal constant GMX_REWARD_ROUTER =
        0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;

    uint32 internal constant TWAP_RANGE_SECS = 1800;
    uint256 public slippage = 9500; // 5%

    constructor(address _vault) BaseStrategy(_vault) {
        ERC20(GMX).approve(STAKED_GMX_TRACKER, type(uint256).max);
    }

    function setSlippage(uint256 _slippage) external onlyStrategist {
        require(_slippage < 10_000, "!_slippage");
        slippage = _slippage;
    }

    function name() external pure override returns (string memory) {
        return "StrategyGMX";
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfUnstakedGmx() public view returns (uint256) {
        return ERC20(GMX).balanceOf(address(this));
    }

    function balanceOfWethRewards() public view returns (uint256) {
        return IRewardTracker(FEE_GMX_TRACKER).claimable(address(this));
    }

    function balanceOfStakedGmx() public view returns (uint256) {
        return
            IRewardTracker(STAKED_GMX_TRACKER).depositBalances(
                address(this),
                GMX
            );
    }

    function _withdrawSome(uint256 _amountNeeded) internal {}

    function _exitPosition(uint256 stYCrvAmount) internal {}

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

    function gmxToWant(uint256 _gmxAmount) public view returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            ETH_GMX_UNI_V3_POOL,
            TWAP_RANGE_SECS
        );
        return
            ethToWant(
                OracleLibrary.getQuoteAtTick(
                    meanTick,
                    uint128(_gmxAmount),
                    GMX,
                    WETH
                )
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
        _wants += gmxToWant(balanceOfUnstakedGmx() + balanceOfStakedGmx());
        _wants += ethToWant(
            balanceOfWethRewards() + ERC20(WETH).balanceOf(address(this))
        );
    }

    function prepareReturn(
        uint256 _debtOutstanding
    )
        internal
        override
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    {}

    function adjustPosition(uint256 _debtOutstanding) internal override {}

    function liquidateAllPositions() internal override returns (uint256) {
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

    function prepareMigration(address _newStrategy) internal override {}

    function protectedTokens()
        internal
        pure
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](3);
        protected[0] = GMX;
        protected[1] = ES_GMX;
        protected[2] = WETH;
        return protected;
    }

    function callMe() external {
        uint256 gmxBal = balanceOfUnstakedGmx();
        console.log("GmxBal", gmxBal);
        IRewardRouterV2(GMX_REWARD_ROUTER).stakeGmx(gmxBal);
        console.log("Staked GMX bal", balanceOfStakedGmx());
    }

    function callMe2() external {
        console.log("Wethr rewards", balanceOfWethRewards());
        // console.log(
        //     IRewardTracker(BN_GMX_TRACKER).claimForAccount(
        //         address(this),
        //         address(this)
        //     )
        // );
        // console.log(ERC20(BN_GMX).balanceOf(address(this)));
    }
}

/*
Stake GMX. 
Staked GMX gives esGMX. We stake it as well to boost wETH rewards.
Unstake GMX and unstake esGMX. We can not sell esGMX but we can sell GMX.
*/
