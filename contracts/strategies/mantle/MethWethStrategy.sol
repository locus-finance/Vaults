// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../abstracts/BaseStrategyForSeparatedVault.sol";
import "../../integrations/circuit/ICircuitVault.sol";
import "../../utils/Utils.sol";
import "../../abstracts/mantle/MoeMerchantStrategyHelper.sol";
import "../../abstracts/mantle/AgniStrategyHelper.sol";
import "../../interfaces/ILocusDataFeed.sol";
import "../../interfaces/ILocusDataFeedUser.sol";

contract MethWethStrategy is
    BaseStrategyForSeparatedVault,
    MoeMerchantStrategyHelper,
    AgniStrategyHelper,
    ILocusDataFeedUser
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    enum ReservedTopics {
        RESERVE_IN_METH_WETH_OF_METH,
        RESERVE_IN_METH_WETH_OF_WETH,
        RESERVE_IN_USDC_METH_OF_USDC,
        RESERVE_IN_USDC_METH_OF_METH
    }

    event MintedCircuitShares(
        uint256 indexed oldBalance,
        uint256 indexed newBalance
    );
    event MintedMoeLp(uint256 indexed oldBalance, uint256 indexed newBalance);
    event BurnedCircuitShares(
        uint256 indexed oldBalance,
        uint256 indexed newBalance
    );
    event BurnedMoeLp(uint256 indexed oldBalance, uint256 indexed newBalance);
    event WantTokensGathered(uint256 indexed amount);

    uint256 private constant STANDARD_SLIPPAGE = 9000;
    uint256 private constant MAX_BPS = 10000;
    ILocusDataFeed public constant LOCUS_DATA_FEED =
        ILocusDataFeed(0x5662AaAc9fdc97910E648e54076Be71D60D4045f);
    uint256 public constant TOPICS_AMOUNT =
        uint256(type(ReservedTopics).max) + 1;

    ICircuitVault public constant CIRCUIT_VAULT =
        ICircuitVault(0x16FA0C5f3eA649259C02c075dbA1C31fc66ea4E0);

    IERC20 public constant WETH =
        IERC20(0xdEAddEaDdeadDEadDEADDEAddEADDEAddead1111);
    IERC20 public constant METH =
        IERC20(0xcDA86A272531e8640cD7F1a92c01839911B90bb0);
    IERC20 public constant MOE_MERCHANT_METH_WETH_POOL =
        IERC20(0x86e3a987187feD135D6d9C114f1857D8144F01e1);

    uint256 public methTokensToAddToMoeLiquidity;
    uint256 public wethTokensToAddToMoeLiquidity;

    function initialize(address _vault, address _strategist) external {
        __Base_Strategy_Initialize(
            _vault,
            _strategist,
            _strategist,
            _strategist
        );
        _agniStrategyHelperInitialize();

        want.forceApprove(address(MOE_ROUTER), type(uint256).max);
        want.forceApprove(address(AGNI_SWAP_ROUTER), type(uint256).max);

        METH.forceApprove(address(MOE_ROUTER), type(uint256).max);
        WETH.forceApprove(address(AGNI_SWAP_ROUTER), type(uint256).max);

        MOE_MERCHANT_METH_WETH_POOL.forceApprove(
            address(MOE_ROUTER),
            type(uint256).max
        );
        MOE_MERCHANT_METH_WETH_POOL.forceApprove(
            address(CIRCUIT_VAULT),
            type(uint256).max
        );
    }

    function setUpLocusDataFeedTopics() external {
        LOCUS_DATA_FEED.setFeed(TOPICS_AMOUNT);
        LOCUS_DATA_FEED.updateFeed(address(this));
    }

    function updateFeedRequested(
        uint256 topicNumber
    ) public view override returns (bytes32 result) {
        if (msg.sender != address(LOCUS_DATA_FEED)) {
            revert OnlyLocusDataFeed();
        }
        IMoePair methWethPair = IMoePair(
            MOE_FACTORY.getPair(address(METH), address(WETH))
        );
        IMoePair usdcMethPair = IMoePair(
            MOE_FACTORY.getPair(address(want), address(METH))
        );

        (uint112 methWethReserve0, uint256 methWethReserve1, ) = methWethPair
            .getReserves();
        (uint112 usdcMethReserve0, uint256 usdcMethReserve1, ) = usdcMethPair
            .getReserves();

        if (
            topicNumber == uint256(ReservedTopics.RESERVE_IN_METH_WETH_OF_METH)
        ) {
            result = bytes32(uint256(methWethReserve0));
        } else if (
            topicNumber == uint256(ReservedTopics.RESERVE_IN_METH_WETH_OF_WETH)
        ) {
            result = bytes32(uint256(methWethReserve1));
        } else if (
            topicNumber == uint256(ReservedTopics.RESERVE_IN_USDC_METH_OF_USDC)
        ) {
            result = bytes32(uint256(usdcMethReserve0));
        } else if (
            topicNumber == uint256(ReservedTopics.RESERVE_IN_USDC_METH_OF_METH)
        ) {
            result = bytes32(uint256(usdcMethReserve1));
        } else {
            revert UnknownTopicNumber(topicNumber);
        }
    }

    function name() external pure override returns (string memory) {
        return "mETH-WETH Strategy";
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfWeth() public view returns (uint256) {
        return WETH.balanceOf(address(this));
    }

    function balanceOfMeth() public view returns (uint256) {
        return METH.balanceOf(address(this));
    }

    function balanceOfCircuitShares() public view returns (uint256) {
        return CIRCUIT_VAULT.balanceOf(address(this));
    }

    function balanceOfMoeLp() public view returns (uint256) {
        return MOE_MERCHANT_METH_WETH_POOL.balanceOf(address(this));
    }

    function wantToCircuitShares(
        uint256 amount
    ) public view returns (uint256 result) {
        if (amount == 0) return 0;
        uint256 usdcForMethSwapAmount = amount / 2;
        uint256 usdcForWethSwapAmount = amount - usdcForMethSwapAmount;

        uint256 wethAmount = _agniQuote(
            address(want),
            address(WETH),
            usdcForWethSwapAmount
        );

        address[] memory path = new address[](2);
        path[0] = address(want);
        path[1] = address(METH);
        IMoePair pair = IMoePair(
            MOE_FACTORY.getPair(address(want), address(METH))
        );
        uint256 methAmount = MOE_ROUTER.getAmountsOut(
            usdcForMethSwapAmount,
            path
        )[1];

        pair = IMoePair(MOE_FACTORY.getPair(address(METH), address(WETH)));
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 lpTotalSupply = pair.totalSupply();

        uint256 liquidity = Math.min(
            (wethAmount * lpTotalSupply) / reserve0,
            (methAmount * lpTotalSupply) / reserve1
        );

        result =
            (liquidity * CIRCUIT_VAULT.totalSupply()) /
            CIRCUIT_VAULT.balance();
    }

    function circuitSharesToWant(
        uint256 amount
    ) public view returns (uint256 result) {
        if (amount == 0) return 0;
        uint256 liquidity = (amount * CIRCUIT_VAULT.balance()) /
            CIRCUIT_VAULT.totalSupply();
        IMoePair pair = IMoePair(
            MOE_FACTORY.getPair(address(METH), address(WETH))
        );
        uint256 lpTotalSupply = pair.totalSupply();
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 methAmount = (liquidity * reserve0) / lpTotalSupply;
        uint256 wethAmount = (liquidity * reserve1) / lpTotalSupply;
        result = _agniQuote(address(WETH), address(want), wethAmount);
        address[] memory path = new address[](2);
        path[0] = address(METH);
        path[1] = address(want);
        result += MOE_ROUTER.getAmountsOut(methAmount, path)[1];
    }

    function _withdrawSome(uint256 _amountNeeded) internal {
        if (_amountNeeded == 0) {
            return;
        }
        uint256 sharesToWithdraw = Math.min(
            wantToCircuitShares(_amountNeeded),
            balanceOfCircuitShares()
        );
        _exitPosition(sharesToWithdraw);
    }

    function estimatedTotalAssets()
        public
        view
        virtual
        override
        returns (uint256 _wants)
    {
        _wants += want.balanceOf(address(this));
        _wants += circuitSharesToWant(balanceOfCircuitShares());
    }

    function prepareReturn(
        uint256 _debtOutstanding
    )
        internal
        override
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    {
        uint256 _totalAssets = estimatedTotalAssets();
        uint256 _totalDebt = vault.getStrategyParams(address(this)).totalDebt;

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
            _mintShares(_excessWant);
        }
    }

    function _exitPosition(uint256 _shares) internal {
        _burnShares(_shares);
    }

    function _mintShares(uint256 _amount) internal {
        if (_amount == 0) return;
        uint256 oldLpBalance = balanceOfMoeLp();

        uint256 usdcForWethSwapAmount = _amount / 2;
        uint256 usdcForMethSwapAmount = _amount - usdcForWethSwapAmount;

        uint256 wethAmount = _agniSwap(
            address(want),
            address(WETH),
            usdcForWethSwapAmount,
            STANDARD_SLIPPAGE
        );

        uint256 usdcMethReserve0 = LOCUS_DATA_FEED.parseUint256FromFeed(
            address(this),
            uint256(ReservedTopics.RESERVE_IN_USDC_METH_OF_USDC)
        );
        uint256 usdcMethReserve1 = LOCUS_DATA_FEED.parseUint256FromFeed(
            address(this),
            uint256(ReservedTopics.RESERVE_IN_USDC_METH_OF_METH)
        );
        uint256 amountMethOut = MOE_ROUTER.getAmountOut(
            usdcForMethSwapAmount,
            usdcMethReserve0,
            usdcMethReserve1
        );
        uint256 methAmount = _moeMerchantSwap(
            address(want),
            address(METH),
            usdcForMethSwapAmount,
            (amountMethOut * STANDARD_SLIPPAGE) / MAX_BPS
        );

        uint256 methWethReserve0 = LOCUS_DATA_FEED.parseUint256FromFeed(
            address(this),
            uint256(ReservedTopics.RESERVE_IN_METH_WETH_OF_METH)
        );
        uint256 methWethReserve1 = LOCUS_DATA_FEED.parseUint256FromFeed(
            address(this),
            uint256(ReservedTopics.RESERVE_IN_METH_WETH_OF_WETH)
        );
        (
            uint256 lpMinted,
            uint256 methLeft,
            uint256 wethLeft
        ) = _moeMerchantAddLiquidity(
                address(METH),
                address(WETH),
                wethAmount + wethTokensToAddToMoeLiquidity,
                methAmount + methTokensToAddToMoeLiquidity,
                methWethReserve0,
                methWethReserve1,
                STANDARD_SLIPPAGE
            );
        methTokensToAddToMoeLiquidity = 0;
        wethTokensToAddToMoeLiquidity = 0;
        if (wethLeft > 0) {
            wethTokensToAddToMoeLiquidity = wethLeft;
        }
        if (methLeft > 0) {
            methTokensToAddToMoeLiquidity = methLeft;
        }
        emit MintedMoeLp(oldLpBalance, balanceOfMoeLp());
        uint256 circuitShares = balanceOfCircuitShares();
        CIRCUIT_VAULT.deposit(lpMinted);
        emit MintedCircuitShares(circuitShares, balanceOfCircuitShares());
    }

    function _burnShares(uint256 _shares) internal {
        if (_shares == 0) return;
        uint256 oldLpBalance = balanceOfMoeLp();
        uint256 oldCircuitSharesBalance = balanceOfCircuitShares();
        CIRCUIT_VAULT.withdraw(_shares);
        emit BurnedCircuitShares(
            oldCircuitSharesBalance,
            balanceOfCircuitShares()
        );
        RemoveLiquidityData
            memory removedLiquidityData = _moeMerchantRemoveLiquidity(
                address(METH),
                address(WETH),
                balanceOfMoeLp() - oldLpBalance
            );
        emit BurnedMoeLp(oldLpBalance, balanceOfMoeLp());

        uint256 swappedFromWethUsdcAmount = _agniSwap(
            address(WETH),
            address(want),
            removedLiquidityData.amountBWithdrawn,
            STANDARD_SLIPPAGE
        );

        uint256 usdcMethReserve0 = LOCUS_DATA_FEED.parseUint256FromFeed(
            address(this),
            uint256(ReservedTopics.RESERVE_IN_USDC_METH_OF_USDC)
        );
        uint256 usdcMethReserve1 = LOCUS_DATA_FEED.parseUint256FromFeed(
            address(this),
            uint256(ReservedTopics.RESERVE_IN_USDC_METH_OF_METH)
        );
        uint256 amountUsdcOut = MOE_ROUTER.getAmountOut(
            removedLiquidityData.amountAWithdrawn,
            usdcMethReserve1,
            usdcMethReserve0
        );
        uint256 swappedFromMethUsdcAmount = _moeMerchantSwap(
            address(METH),
            address(want),
            removedLiquidityData.amountAWithdrawn,
            (amountUsdcOut * STANDARD_SLIPPAGE) / MAX_BPS
        );
        emit WantTokensGathered(
            swappedFromWethUsdcAmount + swappedFromMethUsdcAmount
        );
    }

    function liquidateAllPositions() internal override returns (uint256) {
        _exitPosition(balanceOfCircuitShares());
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
        uint256 wantBalance = balanceOfWant();
        if (wantBalance > 0) {
            _mintShares(wantBalance);
        }
        IERC20(address(CIRCUIT_VAULT)).safeTransfer(
            _newStrategy,
            balanceOfCircuitShares()
        );
    }

    function protectedTokens()
        internal
        pure
        override
        returns (address[] memory protected)
    {
        protected = new address[](4);
        protected[0] = address(CIRCUIT_VAULT);
        protected[1] = address(WETH);
        protected[2] = address(METH);
        protected[4] = address(MOE_MERCHANT_METH_WETH_POOL);
        return protected;
    }

    receive() external payable {}
}
