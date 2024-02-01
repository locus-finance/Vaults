// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.19;

import {BaseStrategy, StrategyParams, VaultAPI} from "@yearn-protocol/contracts/BaseStrategy.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../utils/Utils.sol";
import "../integrations/curve/ICurve.sol";
import "../integrations/convex/IConvexDeposit.sol";
import "../integrations/convex/IConvexRewards.sol";
import "../integrations/convex/IGauge.sol";
import "../integrations/convex/ILPToken.sol";
import "../integrations/weth/IWETH.sol";


contract OriginEthStrategy is BaseStrategy, Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    address public constant LP_TOKEN = 0x94B17476A93b3262d87B9a326965D1E91f9c13E7;
    address public constant CONVEX = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31; 
    address public constant GAUGE = 0xd03BE91b1932715709e18021734fcB91BB431715;
    address public constant REWARDS = 0x24b65DC1cf053A8D96872c323d29e86ec43eB33A;
    address public constant REWARD_TOKEN = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint32 internal constant TWAP_RANGE_SECS = 1800;
    address internal constant CRV_WETH_UNI_POOL = 0x4c83A7f819A5c37D64B4c5A2f8238Ea082fA1f4e;
    address internal constant UNI_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    uint24 internal constant FEE = 10000;
    uint256 public slippage;
    uint256 constant private SLIPPAGE_BASE = 10000;
    uint256 constant private PID = 174;


    constructor(address _vault) BaseStrategy(_vault) {}

    function initialize(address _vault, address _strategist) public initializer {
        _initialize(_vault, _strategist, _strategist, _strategist);
        IERC20(WETH).safeApprove(WETH, type(uint256).max);
        IERC20(REWARD_TOKEN).safeApprove(UNI_ROUTER, type(uint256).max);
        IERC20(LP_TOKEN).safeApprove(CONVEX, type(uint256).max);
        __UUPSUpgradeable_init();
        __Ownable_init();


        slippage = 9000; // 2%
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}


    function ethToWant(uint256 _amtInWei) public view virtual override returns (uint256){
        return 0;
    }

    function setSlippage(uint256 _slippage) external onlyStrategist {
        require(_slippage < 10_000, "!_slippage");
        slippage = _slippage;
    }

    function name() external pure override returns (string memory) {
        return "Origin ETH Strategy";
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfLPUnstaked() public view returns (uint256) {
        return ERC20(LP_TOKEN).balanceOf(address(this));
    }

    function balanceOfLPStaked() public view returns (uint256) {
        return IConvexRewards(REWARDS).balanceOf(address(this));
    }

    function getRewards() public view virtual returns (uint256) {
        return IConvexRewards(REWARDS).earned(address(this));
    }

    function LPToWant(uint256 _lpTokens) public view returns (uint256) {
        if (_lpTokens == 0) return 0;
        return ILPToken(LP_TOKEN).calc_withdraw_one_coin(_lpTokens, 0);
    }

    function wantToLp(uint256 _wantAmount) public view returns(uint256){
        if (_wantAmount == 0) return 0;
        uint256[2] memory amounts = [_wantAmount,0];
       return ILPToken(LP_TOKEN).calc_token_amount(amounts, true); 
    }

    function _withdrawSome(uint256 _amountNeeded) internal {
        if (_amountNeeded == 0) {
            return;
        }
        
            uint256 lpTokensToWithdraw = Math.min(
                wantToLp(_amountNeeded),
                balanceOfLPStaked()
            );
            _exitPosition(lpTokensToWithdraw);
        
    }

    function estimatedTotalAssets()
        public
        view
        virtual
        override
        returns (uint256 _wants)
    {
        _wants = balanceOfWant() + LPToWant(balanceOfLPStaked()) + LPToWant(balanceOfLPUnstaked()) + CrvToWant(getRewards());
        
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
        if (getRewards() > 0) {
            _claimAndSellRewards();
        }
        uint256 _wantBal = balanceOfWant();
        uint256 _excessWant = 0;
        if (_wantBal > _debtOutstanding) {
            _excessWant = _wantBal - _debtOutstanding;
        }
        if (_excessWant > 0) {
            uint256[2] memory amounts = [_excessWant, 0];
            _unwrap(_excessWant);
            uint256 minMintAmount = wantToLp(_excessWant) * slippage / SLIPPAGE_BASE;
            ICurve(LP_TOKEN).add_liquidity{value : _excessWant}(amounts, minMintAmount, address(this));
        }
        if (balanceOfLPUnstaked() > 0) {
           bool suc = IConvexDeposit(CONVEX).deposit(PID, balanceOfLPUnstaked(), true);
           require(suc == true, "unsuccessful operation deposit");
        }
    }

    function smthToSmth(
        address pool,
        address tokenFrom,
        address tokenTo,
        uint256 amount
    ) internal view returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(pool, TWAP_RANGE_SECS);
        return
            OracleLibrary.getQuoteAtTick(
                meanTick,
                uint128(amount),
                tokenFrom,
                tokenTo
            );
    }

    function CrvToWant(
        uint256 amountIn
    ) public view returns (uint256 amountOut) {
        if (amountIn == 0) {
            return 0;
        }
        amountOut = smthToSmth(
            CRV_WETH_UNI_POOL,
            REWARD_TOKEN,
            WETH,
            amountIn
        );
    }

    function _exitPosition(uint256 _stakedLpTokens) internal {
        _claimAndSellRewards();
        bool suc = IConvexRewards(REWARDS).withdrawAndUnwrap(_stakedLpTokens,false);
        require(suc == true, "withdraw unsuccessful");
        uint256 minTokenToRec = LPToWant(balanceOfLPUnstaked()) * slippage / SLIPPAGE_BASE;
        ILPToken(LP_TOKEN).remove_liquidity_one_coin(balanceOfLPUnstaked(), 0, minTokenToRec);
        _wrap(address(this).balance);
    }

    function liquidateAllPositions() internal override returns (uint256) {
        _exitPosition(balanceOfLPStaked());
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
       uint256 assets = liquidateAllPositions();
        want.safeTransfer(_newStrategy, assets);
    }

    function protectedTokens()
        internal
        pure
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](3);
        protected[0] = LP_TOKEN;
        protected[1] = WETH;
        return protected;
    }

    function _claimAndSellRewards() internal {
        if (getRewards() == 0) {
            return;
        }
        bool suc = IConvexRewards(REWARDS).getReward(address(this), true);
        require(suc == true, "unsuccessful");        
        ISwapRouter.ExactInputSingleParams memory params;
        params.tokenIn = REWARD_TOKEN;
        params.tokenOut = WETH;
        params.fee = 10000;
        params.recipient = address(this);
        params.deadline = block.timestamp;
        params.amountIn = IERC20(REWARD_TOKEN).balanceOf(address(this));
        params.amountOutMinimum = CrvToWant(IERC20(REWARD_TOKEN).balanceOf(address(this))) * slippage / SLIPPAGE_BASE;
        params.sqrtPriceLimitX96 = 0;
        ISwapRouter(UNI_ROUTER).exactInputSingle(params);
    }

    function _wrap(uint256 amount)internal{
        IWETH(WETH).deposit{value : amount}();
    }

    function _unwrap(uint256 amount)internal{
        IWETH(WETH).withdraw(amount);
    }

    receive() external payable {}
}