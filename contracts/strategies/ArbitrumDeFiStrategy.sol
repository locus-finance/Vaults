// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use
pragma solidity ^0.8.18;

import {DexSwapper, IERC20, IV3SwapRouter, IWETH, IUniswapV3Factory} from "../utils/DexSwapper.sol";
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
    ICamelotRouter public camelotRouter;
    IPositionHelper public camelotPositionHelper;
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
        address _camelotPositionHelper,
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
        camelotPositionHelper = IPositionHelper(_camelotPositionHelper);
        camelotRouter = ICamelotRouter(_camelotRouter);
        gnsStackingContract = IGNSStakingV6_2(_gnsStackingContract);

        ARB_TOKEN.approve(address(gnsStackingContract), type(uint256).max);
        GMX_TOKEN.approve(
            address(rewardRouter.stakedGmxTracker()),
            type(uint256).max
        );
        GMX_TOKEN.approve(address(rewardRouter), type(uint256).max);
        GRAIL_TOKEN.approve(address(camelotPositionHelper), type(uint256).max);
        GNS_TOKEN.approve(address(gnsStackingContract), type(uint256).max);
        IERC20(_weth).approve(address(amm), type(uint256).max);
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

    function name() external pure override returns (string memory) {
        return "StrategyArbitrumDeFi";
    }

    /// @notice Balance of want sitting in our strategy.
    function balanceOfWant() public view override returns (uint256) {
        return want.balanceOf(address(this));
    }

    function estimatedTotalAssets()
        public
        view
        override
        returns (uint256 _wants)
    {
        _wants = balanceOfWant();
        uint256 gnsTokens;
        uint256 gmxTokens;
        uint256 arbTokens;
        uint256 grailTokens;
        // todo
        return _wants + gnsTokens + gmxTokens + arbTokens + grailTokens;
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

    function _depositToCamelot(
        address _tokenA,
        address _tokenB,
        address _camelotNFTStackingPool
    ) internal {
        camelotPositionHelper.addLiquidityAndCreatePosition(
            _tokenA,
            _tokenB,
            IERC20(_tokenA).balanceOf(address(this)),
            IERC20(_tokenB).balanceOf(address(this)),
            IERC20(_tokenA).balanceOf(address(this)),
            IERC20(_tokenB).balanceOf(address(this)),
            block.timestamp + _DEAD_LINE,
            address(this),
            INFTPool(_camelotNFTStackingPool),
            0
        );
    }

    function _depositToGNS() internal {
        gnsStackingContract.stakeTokens(GNS_TOKEN.balanceOf(address(this)));
    }

    function _depositToGMX() internal {
        rewardRouter.stakeGmx(GMX_TOKEN.balanceOf(address(this)));
    }

    function _withdrawFromPositionFromCamelot(
        address _nftPool,
        uint256 _nftId
    ) internal {
        uint amountTokenMin;
        uint amountETHMin;
        uint8 v;
        bytes32 r;
        bytes32 s;
        (address lpToken, , , , , , , ) = INFTPool(_nftPool).getPoolInfo();
        INFTPool(_nftPool).withdrawFromPosition(
            _nftId,
            INFTPool(_nftPool).balanceOf(address(this))
        );
        ICamelotRouter(camelotRouter)
            .removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
                lpToken,
                IERC20(lpToken).balanceOf(address(this)),
                amountTokenMin,
                amountETHMin,
                address(this),
                _DEAD_LINE,
                true,
                v,
                r,
                s
            );
    }

    function _withdrawalFromGNS() internal {
        gnsStackingContract.unstakeTokens(GNS_TOKEN.balanceOf(address(this))); //todo
    }

    function _withdrawalFromGMX() internal {
        rewardRouter.unstakeGmx(
            IERC20(rewardRouter.feeGmxTracker()).balanceOf(address(this))
        );
    }

    function _claimAllRewards() internal {
        rewardRouter.handleRewards(true, false, true, false, false, true, true);
        gnsStackingContract.harvest();
    }
}
