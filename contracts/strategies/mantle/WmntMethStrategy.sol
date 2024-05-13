// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {BaseStrategy} from "@yearn-protocol/contracts/BaseStrategy.sol";
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

contract WmntMethStrategy is
    BaseStrategyForSeparatedVault,
    MoeMerchantStrategyHelper,
    AgniStrategyHelper,
    ILocusDataFeedUser
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    enum ReservedTopics {
        RESERVE_IN_WMNT_METH_OF_WMNT,
        RESERVE_IN_WMNT_METH_OF_METH
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
    uint256 public constant TOPICS_AMOUNT = uint256(type(ReservedTopics).max) + 1;

    ICircuitVault public constant CIRCUIT_VAULT =
        ICircuitVault(0xc37c7dEBa5E7F5dE572C914D5c159EA08DE1fefF);
    IERC20 public constant WMNT =
        IERC20(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8);
    IERC20 public constant METH =
        IERC20(0xcDA86A272531e8640cD7F1a92c01839911B90bb0);
    IERC20 public constant MOE_MERCHANT_WMNT_METH_POOL =
        IERC20(0xa375ea3e1f92d62e3A71B668bAb09f7155267fa3);

    uint256 public wmntTokensToAddToMoeLiquidity;
    uint256 public methTokensToAddToMoeLiquidity;

    function initialize(address _vault, address _strategist) external {
        __Base_Strategy_Initialize(
            _vault,
            _strategist,
            _strategist,
            _strategist
        );
        _agniStrategyHelperInitialize();
        
        want.approve(address(MOE_ROUTER), type(uint256).max);
        want.approve(address(AGNI_SWAP_ROUTER), type(uint256).max);

        WMNT.approve(address(AGNI_SWAP_ROUTER), type(uint256).max);
        METH.approve(address(AGNI_SWAP_ROUTER), type(uint256).max);
        
        MOE_MERCHANT_WMNT_METH_POOL.approve(
            address(MOE_ROUTER),
            type(uint256).max
        );
        MOE_MERCHANT_WMNT_METH_POOL.approve(
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
        IMoePair wmntMethPair = IMoePair(MOE_FACTORY.getPair(address(WMNT), address(METH)));
        (uint112 wmntMethReserve0, uint256 wmntMethReserve1,) = wmntMethPair.getReserves();
        if (topicNumber == uint256(ReservedTopics.RESERVE_IN_WMNT_METH_OF_WMNT)) {
            result = bytes32(uint256(wmntMethReserve0));
        } else if (topicNumber == uint256(ReservedTopics.RESERVE_IN_WMNT_METH_OF_METH)) {
            result = bytes32(uint256(wmntMethReserve1));
        } else {
            revert UnknownTopicNumber(topicNumber);
        }
    }

    function name() external pure override returns (string memory) {
        return "wMNT-METH LP Strategy";
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfWmnt() public view returns (uint256) {
        return WMNT.balanceOf(address(this));
    }

    function balanceOfMeth() public view returns (uint256) {
        return METH.balanceOf(address(this));
    }

    function balanceOfCircuitShares() public view returns (uint256) {
        return CIRCUIT_VAULT.balanceOf(address(this));
    }

    function balanceOfMoeLp() public view returns (uint256) {
        return MOE_MERCHANT_WMNT_METH_POOL.balanceOf(address(this));
    }

    function wantToCircuitShares(
        uint256 amount
    ) public view returns (uint256 result) {
        if (amount == 0) return 0;
        uint256 usdcForMethSwapAmount = amount / 2;
        uint256 usdcForWmntSwapAmount = amount - usdcForMethSwapAmount;
        uint256 methAmount = _agniQuote(address(want), address(METH), usdcForMethSwapAmount);
        uint256 wmntAmount = _agniQuote(address(want), address(WMNT), usdcForWmntSwapAmount);
        IMoePair pair = IMoePair(
            MOE_FACTORY.getPair(address(WMNT), address(METH))
        );
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 lpTotalSupply = pair.totalSupply();
        
        uint256 liquidity = Math.min(
            (methAmount * lpTotalSupply) / reserve0,
            (wmntAmount * lpTotalSupply) / reserve1
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
            MOE_FACTORY.getPair(address(WMNT), address(METH))
        );
        uint256 lpTotalSupply = pair.totalSupply();
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 wmntAmount = (liquidity * reserve0) / lpTotalSupply;
        uint256 methAmount = (liquidity * reserve1) / lpTotalSupply; 
        result = _agniQuote(address(METH), address(want), methAmount);
        result += _agniQuote(address(WMNT), address(want), wmntAmount);
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
        
        uint256 usdcForMethSwapAmount = _amount / 2;
        uint256 usdcForWmntSwapAmount = _amount - usdcForMethSwapAmount;
        
        uint256 methAmount = _agniSwap(address(want), address(METH), usdcForMethSwapAmount);
        uint256 wmntAmount = _agniSwap(address(want), address(WMNT), usdcForWmntSwapAmount);

        uint256 wmntMethReserve0 = LOCUS_DATA_FEED.parseUint256FromFeed(
            address(this),
            uint256(ReservedTopics.RESERVE_IN_WMNT_METH_OF_WMNT)
        );
        uint256 wmntMethReserve1 = LOCUS_DATA_FEED.parseUint256FromFeed(
            address(this),
            uint256(ReservedTopics.RESERVE_IN_WMNT_METH_OF_METH)
        );
        (uint256 lpMinted, uint256 wmntLeft, uint256 methLeft) = _moeMerchantAddLiquidity(
            address(WMNT),
            address(METH),
            methAmount + methTokensToAddToMoeLiquidity,
            wmntAmount + wmntTokensToAddToMoeLiquidity,
            wmntMethReserve0,
            wmntMethReserve1
        );
        methTokensToAddToMoeLiquidity = 0;
        wmntTokensToAddToMoeLiquidity = 0;
        if (methLeft > 0) {
            methTokensToAddToMoeLiquidity = methLeft;
        }
        if (wmntLeft > 0) {
            wmntTokensToAddToMoeLiquidity = wmntLeft;
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
                address(WMNT),
                address(METH),
                balanceOfMoeLp() - oldLpBalance
            );
        emit BurnedMoeLp(oldLpBalance, balanceOfMoeLp());

        uint256 swappedFromWmntUsdcAmount = _agniSwap(address(WMNT), address(want), removedLiquidityData.amountAWithdrawn);
        uint256 swappedFromMethhUsdcAmount = _agniSwap(address(METH), address(want), removedLiquidityData.amountBWithdrawn);

        emit WantTokensGathered(
            swappedFromWmntUsdcAmount + swappedFromMethhUsdcAmount
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
        protected[1] = address(WMNT);
        protected[2] = address(METH);
        protected[4] = address(MOE_MERCHANT_WMNT_METH_POOL);
        return protected;
    }

    receive() external payable {}
}
