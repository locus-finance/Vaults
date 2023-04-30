// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {DexSwapper, IERC20} from "./DexSwapper.sol";
import {BaseStrategyInitializable, StrategyParams} from "./../BaseStrategy.sol";
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

    IRewardRouterV2 public mintRouter;

    // IRewardRouterV2 public rewardRouter;
    IGlpManager public glpManager;
    //IVault public gmxVault;
    IERC20 public glpToken;

    IERC20 public glpTrackerToken;

    constructor(address _vault) BaseStrategyInitializable(_vault) {
        // todo
        //want.approve(address(...), type(uint256).max);
        //IGMX(gmx).approve(..., type(uint256).max);
        //ICamelot(glp).approve(address(...), type(uint256).max);
        //IERC20(camelot).approve(address(...), type(uint256).max);
        // IERC20(WETH).approve(address(amm), type(uint256).max);
        // amm = IV3SwapRouter("0x0");
        // WETH = "0x0";
        // factory = IUniswapV3Factory("0x0");
        //fees = [0, 100, 300, 3000];
        // glpManager =
        // glpToken =
        // glpTrackerToken =
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
            glpToken.totalSupply();
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
        require(amount > 0, "ArbitrumDeFiStrategy::buyGLP::zero amount");
        if (address(token) == address(0x0)) {
            require(
                address(this).balance >= amount,
                "ArbitrumDeFiStrategy::buyGLP::bridge or deposit native currency"
            );
            glpBoughtAmount = mintRouter.mintAndStakeGlpETH{value: amount}(
                minUsdg,
                minGlp
            );
        } else {
            require(
                token.balanceOf(address(this)) >= amount,
                "GMX Vault::buyGLP::bridge or deposit assets"
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
                "ArbitrumDeFiStrategy::buyGLP::glp buying failed"
            );
        }
        //  emit BuyingGMX(token, amount, glpBoughtAmount);
    }
}
