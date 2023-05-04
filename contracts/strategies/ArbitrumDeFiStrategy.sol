// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {DexSwapper, IERC20, IV3SwapRouter, IWETH, IUniswapV3Factory} from "./DexSwapper.sol";
import {BaseStrategyInitializable, StrategyParams} from "@yearn-protocol/contracts/BaseStrategy.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IArbitrumDeFiStrategy.sol";

contract ArbitrumDeFiStrategy is
    BaseStrategyInitializable,
    DexSwapper,
    IArbitrumDeFiStrategy
{
    using SafeERC20 for IERC20;

    bool public claimRewards = true; // claim rewards when withdrawAndUnwrap
    uint256 public slippage = 9800; // 2%

    IERC20 public constant ARB_TOKEN =
        IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548);
    IERC20 public constant GNS_TOKEN =
        IERC20(0x18c11FD286C5EC11c3b683Caa813B77f5163A122);
    IERC20 public constant USDT_TOKEN =
        IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    IERC20 public constant GMX_TOKEN =
        IERC20(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a);
    IERC20 public constant GRAIL_TOKEN =
        IERC20(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);

    IRewardRouterV2 public mintRouter;
    IRewardRouterV2 public rewardRouter;
    IPositionHelper public camelotRouter;
    IGlpManager public glpManager;
    IERC20 public glpTrackerToken;
    IGNSStakingV6_2 public gnsStackingContract;
    uint256 private constant _DEAD_LINE = 90000;

    constructor(
        address _vault,
        address _weth,
        address _amm,
        address _uniFactory,
        address _gmxRewardRouter,
        address _camelotRouter,
        address _gnsStackingContract
    ) BaseStrategyInitializable(_vault) {
        amm = IV3SwapRouter(_amm);
        WETH = _weth;
        factory = IUniswapV3Factory(_uniFactory);
        fees = [0, 100, 300, 3000];
        rewardRouter = IRewardRouterV2(_gmxRewardRouter);
        glpManager = IGlpManager(rewardRouter.glpManager());
        glpTrackerToken = IERC20(rewardRouter.stakedGlpTracker());
        camelotRouter = IPositionHelper(_camelotRouter);
        gnsStackingContract = IGNSStakingV6_2(_gnsStackingContract);

        ARB_TOKEN.approve(address(gnsStackingContract), type(uint256).max);
        GMX_TOKEN.approve(
            address(rewardRouter.stakedGmxTracker()),
            type(uint256).max
        );
        GRAIL_TOKEN.approve(address(camelotRouter), type(uint256).max);
        GNS_TOKEN.approve(address(gnsStackingContract), type(uint256).max);
        IERC20(_weth).approve(address(amm), type(uint256).max);
    }

    function name() external pure override returns (string memory) {
        return "ArbitrumDeFi";
    }

    function setSlippage(uint256 _slippage) external onlyStrategist {
        require(_slippage < 10_000, "!_slippage");
        slippage = _slippage;
    }

    function buyTokens(
        address baseToken,
        address[] memory tokens,
        uint256[] memory amount
    ) external payable override onlyStrategist {
        for (uint256 i = 0; i < tokens.length; i++) {
            _swap(baseToken, tokens[i], amount[i], address(this));
        }
    }

    function buyToken(
        address baseToken,
        address token,
        uint256 amount
    ) external payable override onlyStrategist {
        _swap(baseToken, token, amount, address(this));
    }

    function setDex(
        address newFactory,
        address newAmm
    ) external override onlyStrategist {
        _setDex(newFactory, newAmm);
    }

    function setFeesLevels(
        uint24[] memory newFees
    ) external override onlyStrategist {
        _setFeesLevels(newFees);
    }

    /// @notice Balance of want sitting in our strategy.
    function balanceOfWant() public view override returns (uint256) {
        return want.balanceOf(address(this));
    }

    function estimatedTotalAssets()
        public
        pure
        override
        returns (uint256 _wants)
    {
        return _wants;
    }

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(
        uint256 _amtInWei
    ) public view virtual override returns (uint256) {
        return _amtInWei;
    }

    function getGMXTvl() public view override returns (uint256) {
        uint256 glpPrice = (glpManager.getAumInUsdg(true) * 1e18) /
            IERC20(glpManager.glp()).totalSupply();
        uint256 fsGlpAmount = glpTrackerToken.balanceOf(address(this));
        return (fsGlpAmount * glpPrice) / 1e18;
    }

    function prepareReturn(
        uint256 _debtOutstanding
    )
        internal
        override
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    {}

    function adjustPosition(uint256 _debtOutstanding) internal override {
        // IPositionHelper(camelotHelperAddress).addLiquidityAndCreatePosition();
        //IGNSStakingV6_2(gnsStakingAddress).stakeTokens();
    }

    function withdrawSome(uint256 _amountNeeded) internal {}

    function liquidateAllPositions() internal override returns (uint256) {}

    function liquidatePosition(
        uint256 _amountNeeded
    ) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {}

    function prepareMigration(address _newStrategy) internal override {
        //
    }

    function protectedTokens()
        internal
        pure
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](4);
        ///
        return protected;
    }

    function _buyGLP(
        IERC20 token,
        uint256 amount,
        uint256 minUsdg,
        uint256 minGlp
    ) internal returns (uint256 glpBoughtAmount) {
        require(amount > 0, "buyGLP:zero amount");
        if (address(token) == address(0x0)) {
            require(
                address(this).balance >= amount,
                "buyGLP:bridge or deposit native currency"
            );
            glpBoughtAmount = mintRouter.mintAndStakeGlpETH{value: amount}(
                minUsdg,
                minGlp
            );
        } else {
            require(
                token.balanceOf(address(this)) >= amount,
                "buyGLP:bridge or deposit assets"
            );

            token.approve(address(mintRouter), amount);
            token.approve(address(glpManager), amount);

            uint256 glpBalanceBefore = glpTrackerToken.balanceOf(address(this));
            // // buy Glp
            glpBoughtAmount = mintRouter.mintAndStakeGlp(
                address(token), // the token to buy GLP with
                amount, // the amount of token to use for the purchase
                minUsdg, // the minimum acceptable USD value of the GLP purchased
                minGlp // minimum acceptable GLP amount
            );
            // check glp balance after buying
            uint256 glpBalanceAfter = glpTrackerToken.balanceOf(address(this));
            require(
                glpBalanceBefore + glpBoughtAmount <= glpBalanceAfter,
                "buyGLP:glp buying failed"
            );
        }
    }

    /**
     *   @notice Sell / unstake and redeem GLP
     *   @dev tokenOut : the token to sell GLP for
     *   @dev glpAmount : the amount of GLP to sell
     *   @dev minOut : the minimum acceptable amount of tokenOut to be received
     *   @return amountPayed payed for the sell
     *   @dev access restricted to only self base building block call
     * */
    function _sellGLP(
        IERC20 tokenOut,
        uint256 glpAmount,
        uint256 minOut
    ) internal returns (uint256 amountPayed) {
        if (address(tokenOut) == address(0x0)) {
            amountPayed = mintRouter.unstakeAndRedeemGlpETH(
                glpAmount,
                minOut,
                payable(address(this))
            );
        } else {
            // unstake And Redeem Glp
            uint256 tokenOutBalanceBefore = tokenOut.balanceOf(address(this));
            amountPayed = mintRouter.unstakeAndRedeemGlp(
                address(tokenOut),
                glpAmount,
                minOut,
                address(this)
            );
            // get contract balance after selling
            uint256 tokenOutBalanceAfter = tokenOut.balanceOf(address(this));

            // get balance change
            uint256 balanceChange = tokenOutBalanceAfter -
                tokenOutBalanceBefore;

            // check if vault balance reflects the sale
            require(balanceChange >= amountPayed, "sellGLP:glp selling failed");
        }
        return amountPayed;
    }

    /**
     *  @notice  rewards compounding and claims them
     *  @dev _shouldClaimGmx boolean yes/no
     *  @dev _shouldStakeGmx boolean yes/no
     *  @dev _shouldClaimEsGmx boolean yes/no
     *  @dev _shouldStakeEsGmx boolean yes/no
     *  @dev _shouldStakeMultiplierPoints boolean yes/no
     *  @dev _shouldClaimWeth boolean yes/no
     *  @dev _shouldConvertWethToEth boolean yes/no
     *  @dev 15 average min cool down time
     *  @dev access restricted to only self base building block call
     */
    function _claimGMXRewards(
        bool shouldClaimGmx,
        bool shouldStakeGmx,
        bool shouldClaimEsGmx,
        bool shouldStakeEsGmx,
        bool shouldStakeMultiplierPoints,
        bool shouldClaimWeth,
        bool shouldConvertWethToEth
    ) internal returns (bool) {
        rewardRouter.handleRewards(
            shouldClaimGmx,
            shouldStakeGmx,
            shouldClaimEsGmx,
            shouldStakeEsGmx,
            shouldStakeMultiplierPoints,
            shouldClaimWeth,
            shouldConvertWethToEth
        );
        return true;
    }

    function _depositToCamelot(
        address _token,
        uint256 _amount,
        address _camelotNFTStackingPool,
        uint256 _value
    ) internal {
        uint256 amountETHMin = 0; // todo
        camelotRouter.addLiquidityETHAndCreatePosition(
            _token,
            _amount,
            _amount,
            amountETHMin,
            block.timestamp + _DEAD_LINE, // todo
            msg.sender,
            INFTPool(_camelotNFTStackingPool),
            0
        );
    }

    function _depositToGNS(uint256 _amount) internal {
        gnsStackingContract.stakeTokens(_amount);
    }
}
