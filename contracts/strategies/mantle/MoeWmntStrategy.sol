// // SPDX-License-Identifier: AGPL-3.0

// pragma solidity ^0.8.18;

// import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
// import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// import "../../abstracts/BaseStrategyForSeparatedVault.sol";
// import "../../integrations/circuit/ICircuitVault.sol";
// import "../../utils/Utils.sol";
// import "../../abstracts/mantle/MoeMerchantStrategyHelper.sol";
// import "../../abstracts/mantle/AgniStrategyHelper.sol";
// import "../../interfaces/ILocusDataFeed.sol";
// import "../../interfaces/ILocusDataFeedUser.sol";

// contract MoeWmntStrategy is
//     BaseStrategyForSeparatedVault,
//     MoeMerchantStrategyHelper,
//     AgniStrategyHelper,
//     ILocusDataFeedUser
// {
//     using SafeERC20 for IERC20;
//     using Math for uint256;

//     enum ReservedTopics {
//         RESERVE_IN_MOE_WMNT_OF_MOE,
//         RESERVE_IN_MOE_WMNT_OF_WMNT,
//         RESERVE_IN_USDC_USDT_OF_USDC,
//         RESERVE_IN_USDC_USDT_OF_USDT,
//         RESERVE_IN_USDT_MOE_OF_USDT,
//         RESERVE_IN_USDT_MOE_OF_MOE
//     }

//     event MintedCircuitShares(
//         uint256 indexed oldBalance,
//         uint256 indexed newBalance
//     );
//     event MintedMoeLp(uint256 indexed oldBalance, uint256 indexed newBalance);
//     event BurnedCircuitShares(
//         uint256 indexed oldBalance,
//         uint256 indexed newBalance
//     );
//     event BurnedMoeLp(uint256 indexed oldBalance, uint256 indexed newBalance);
//     event WantTokensGathered(uint256 indexed amount);

//     uint256 private constant STANDARD_SLIPPAGE = 9000;
//     uint256 private constant MAX_BPS = 10000;
//     ILocusDataFeed public constant LOCUS_DATA_FEED =
//         ILocusDataFeed(0x5662AaAc9fdc97910E648e54076Be71D60D4045f);
//     uint256 public constant TOPICS_AMOUNT =
//         uint256(type(ReservedTopics).max) + 1;

//     ICircuitVault public constant CIRCUIT_VAULT =
//         ICircuitVault(0xa3647389cf2bF9279ab239d3710bB8a2eFE0BC8B);

//     IERC20 public constant USDT =
//         IERC20(0x201EBa5CC46D216Ce6DC03F6a759e8E766e956aE);
//     IERC20 public constant MOE =
//         IERC20(0x4515A45337F461A11Ff0FE8aBF3c606AE5dC00c9);
//     IERC20 public constant WMNT =
//         IERC20(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8);

//     IERC20 public constant MOE_MERCHANT_MOE_WMNT_POOL =
//         IERC20(0x763868612858358f62b05691dB82Ad35a9b3E110);

//     uint256 public moeTokensToAddToMoeLiquidity;
//     uint256 public wmntTokensToAddToMoeLiquidity;

//     function initialize(address _vault, address _strategist) external {
//         __Base_Strategy_Initialize(
//             _vault,
//             _strategist,
//             _strategist,
//             _strategist
//         );
//         _agniStrategyHelperInitialize();
//         want.forceApprove(address(MOE_ROUTER), type(uint256).max);
//         USDT.forceApprove(address(MOE_ROUTER), type(uint256).max);
//         MOE.forceApprove(address(MOE_ROUTER), type(uint256).max);
//         want.forceApprove(address(AGNI_SWAP_ROUTER), type(uint256).max);
//         WMNT.forceApprove(address(AGNI_SWAP_ROUTER), type(uint256).max);
//         MOE_MERCHANT_MOE_WMNT_POOL.forceApprove(
//             address(MOE_ROUTER),
//             type(uint256).max
//         );
//         MOE_MERCHANT_MOE_WMNT_POOL.forceApprove(
//             address(CIRCUIT_VAULT),
//             type(uint256).max
//         );
//     }

//     function setUpLocusDataFeedTopics() external {
//         LOCUS_DATA_FEED.setFeed(TOPICS_AMOUNT);
//         LOCUS_DATA_FEED.updateFeed(address(this));
//     }

//     function updateFeedRequested(
//         uint256 topicNumber
//     ) public view override returns (bytes32 result) {
//         if (msg.sender != address(LOCUS_DATA_FEED)) {
//             revert OnlyLocusDataFeed();
//         }
//         IMoePair moeWmntPair = IMoePair(
//             MOE_FACTORY.getPair(address(MOE), address(WMNT))
//         );
//         IMoePair usdcUsdtPair = IMoePair(
//             MOE_FACTORY.getPair(address(want), address(USDT))
//         );
//         IMoePair usdtMoePair = IMoePair(
//             MOE_FACTORY.getPair(address(USDT), address(MOE))
//         );

//         (uint112 moeWmntReserve0, uint256 moeWmntReserve1, ) = moeWmntPair
//             .getReserves();
//         (uint112 usdcUsdtReserve0, uint256 usdcUsdtReserve1, ) = usdcUsdtPair
//             .getReserves();
//         (uint112 usdtMoeReserve0, uint256 usdtMoeReserve1, ) = usdtMoePair
//             .getReserves();

//         if (topicNumber == uint256(ReservedTopics.RESERVE_IN_MOE_WMNT_OF_MOE)) {
//             result = bytes32(uint256(moeWmntReserve0));
//         } else if (
//             topicNumber == uint256(ReservedTopics.RESERVE_IN_MOE_WMNT_OF_WMNT)
//         ) {
//             result = bytes32(uint256(moeWmntReserve1));
//         } else if (
//             topicNumber == uint256(ReservedTopics.RESERVE_IN_USDC_USDT_OF_USDC)
//         ) {
//             result = bytes32(uint256(usdcUsdtReserve0));
//         } else if (
//             topicNumber == uint256(ReservedTopics.RESERVE_IN_USDC_USDT_OF_USDT)
//         ) {
//             result = bytes32(uint256(usdcUsdtReserve1));
//         } else if (
//             topicNumber == uint256(ReservedTopics.RESERVE_IN_USDT_MOE_OF_USDT)
//         ) {
//             result = bytes32(uint256(usdtMoeReserve0));
//         } else if (
//             topicNumber == uint256(ReservedTopics.RESERVE_IN_USDT_MOE_OF_MOE)
//         ) {
//             result = bytes32(uint256(usdtMoeReserve1));
//         } else {
//             revert UnknownTopicNumber(topicNumber);
//         }
//     }

//     function name() external pure override returns (string memory) {
//         return "MOE-WMNT Strategy";
//     }

//     function balanceOfWant() public view returns (uint256) {
//         return want.balanceOf(address(this));
//     }

//     function balanceOfWmnt() public view returns (uint256) {
//         return WMNT.balanceOf(address(this));
//     }

//     function balanceOfUsdt() public view returns (uint256) {
//         return USDT.balanceOf(address(this));
//     }

//     function balanceOfMoe() public view returns (uint256) {
//         return MOE.balanceOf(address(this));
//     }

//     function balanceOfCircuitShares() public view returns (uint256) {
//         return CIRCUIT_VAULT.balanceOf(address(this));
//     }

//     function balanceOfMoeLp() public view returns (uint256) {
//         return MOE_MERCHANT_MOE_WMNT_POOL.balanceOf(address(this));
//     }

//     function wantToCircuitShares(
//         uint256 amount
//     ) public view returns (uint256 result) {
//         if (amount == 0) return 0;
//         uint256 usdcForUsdtSwapAmount = amount / 2;
//         uint256 usdcForWmntSwapAmount = amount - usdcForUsdtSwapAmount;

//         uint256 wmntAmount = _agniQuote(
//             address(want),
//             address(WMNT),
//             usdcForWmntSwapAmount
//         );

//         address[] memory path = new address[](2);
//         path[0] = address(want);
//         path[1] = address(USDT);
//         IMoePair pair = IMoePair(
//             MOE_FACTORY.getPair(address(want), address(USDT))
//         );
//         uint256 usdtAmount = MOE_ROUTER.getAmountsOut(
//             usdcForUsdtSwapAmount,
//             path
//         )[1];

//         path[0] = address(USDT);
//         path[1] = address(MOE);
//         uint256 moeAmount = MOE_ROUTER.getAmountsOut(usdtAmount, path)[1];

//         pair = IMoePair(MOE_FACTORY.getPair(address(MOE), address(WMNT)));

//         (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
//         uint256 lpTotalSupply = pair.totalSupply();

//         uint256 liquidity = Math.min(
//             (wmntAmount * lpTotalSupply) / reserve0,
//             (moeAmount * lpTotalSupply) / reserve1
//         );

//         result =
//             (liquidity * CIRCUIT_VAULT.totalSupply()) /
//             CIRCUIT_VAULT.balance();
//     }

//     function circuitSharesToWant(
//         uint256 amount
//     ) public view returns (uint256 result) {
//         if (amount == 0) return 0;
//         uint256 liquidity = (amount * CIRCUIT_VAULT.balance()) /
//             CIRCUIT_VAULT.totalSupply();

//         IMoePair pair = IMoePair(
//             MOE_FACTORY.getPair(address(MOE), address(WMNT))
//         );
//         uint256 lpTotalSupply = pair.totalSupply();
//         (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

//         uint256 moeAmount = (liquidity * reserve0) / lpTotalSupply;
//         uint256 wmntAmount = (liquidity * reserve1) / lpTotalSupply;

//         result = _agniQuote(address(WMNT), address(want), wmntAmount);

//         address[] memory path = new address[](2);

//         path[0] = address(MOE);
//         path[1] = address(USDT);
//         uint256 usdtAmount = MOE_ROUTER.getAmountsOut(moeAmount, path)[1];
//         path[0] = address(USDT);
//         path[1] = address(want);

//         result += MOE_ROUTER.getAmountsOut(usdtAmount, path)[1];
//     }

//     function _withdrawSome(uint256 _amountNeeded) internal {
//         if (_amountNeeded == 0) {
//             return;
//         }
//         uint256 sharesToWithdraw = Math.min(
//             wantToCircuitShares(_amountNeeded),
//             balanceOfCircuitShares()
//         );
//         _exitPosition(sharesToWithdraw);
//     }

//     function estimatedTotalAssets()
//         public
//         view
//         virtual
//         override
//         returns (uint256 _wants)
//     {
//         _wants += want.balanceOf(address(this));
//         _wants += circuitSharesToWant(balanceOfCircuitShares());
//     }

//     function prepareReturn(
//         uint256 _debtOutstanding
//     )
//         internal
//         override
//         returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
//     {
//         uint256 _totalAssets = estimatedTotalAssets();
//         uint256 _totalDebt = vault.getStrategyParams(address(this)).totalDebt;

//         if (_totalAssets >= _totalDebt) {
//             _profit = _totalAssets - _totalDebt;
//             _loss = 0;
//         } else {
//             _profit = 0;
//             _loss = _totalDebt - _totalAssets;
//         }
//         uint256 _liquidWant = balanceOfWant();
//         uint256 _amountNeeded = _debtOutstanding + _profit;
//         if (_liquidWant <= _amountNeeded) {
//             _withdrawSome(_amountNeeded - _liquidWant);
//             _liquidWant = balanceOfWant();
//         }
//         // enough to pay profit (partial or full) only
//         if (_liquidWant <= _profit) {
//             _profit = _liquidWant;
//             _debtPayment = 0;
//             // enough to pay for all profit and _debtOutstanding (partial or full)
//         } else {
//             _debtPayment = Math.min(_liquidWant - _profit, _debtOutstanding);
//         }
//     }

//     function adjustPosition(uint256 _debtOutstanding) internal override {
//         if (emergencyExit) {
//             return;
//         }

//         uint256 _wantBal = balanceOfWant();
//         uint256 _excessWant = 0;
//         if (_wantBal > _debtOutstanding) {
//             _excessWant = _wantBal - _debtOutstanding;
//         }

//         if (_excessWant > 0) {
//             _mintShares(_excessWant);
//         }
//     }

//     function _exitPosition(uint256 _shares) internal {
//         _burnShares(_shares);
//     }

//     function _mintShares(uint256 _amount) internal {
//         if (_amount == 0) return;
//         uint256 oldLpBalance = balanceOfMoeLp();

//         uint256 usdcForUsdtSwapAmount = _amount / 2;
//         uint256 usdcForWmntSwapAmount = _amount - usdcForUsdtSwapAmount;

//         uint256 wmntAmount = _agniSwap(
//             address(want),
//             address(WMNT),
//             usdcForWmntSwapAmount,
//             STANDARD_SLIPPAGE
//         );

//         uint256 usdcUsdtReserve0 = LOCUS_DATA_FEED.parseUint256FromFeed(
//             address(this),
//             uint256(ReservedTopics.RESERVE_IN_USDC_USDT_OF_USDC)
//         );
//         uint256 usdcUsdtReserve1 = LOCUS_DATA_FEED.parseUint256FromFeed(
//             address(this),
//             uint256(ReservedTopics.RESERVE_IN_USDC_USDT_OF_USDT)
//         );
//         uint256 amountUsdtOut = MOE_ROUTER.getAmountOut(
//             usdcForUsdtSwapAmount,
//             usdcUsdtReserve0,
//             usdcUsdtReserve1
//         );
//         uint256 usdtAmount = _moeMerchantSwap(
//             address(want),
//             address(USDT),
//             usdcForUsdtSwapAmount,
//             (amountUsdtOut * STANDARD_SLIPPAGE) / MAX_BPS
//         );

//         uint256 usdtMoeReserve0 = LOCUS_DATA_FEED.parseUint256FromFeed(
//             address(this),
//             uint256(ReservedTopics.RESERVE_IN_USDT_MOE_OF_USDT)
//         );
//         uint256 usdtMoeReserve1 = LOCUS_DATA_FEED.parseUint256FromFeed(
//             address(this),
//             uint256(ReservedTopics.RESERVE_IN_USDT_MOE_OF_MOE)
//         );
//         uint256 amountMoeOut = MOE_ROUTER.getAmountOut(
//             usdtAmount,
//             usdtMoeReserve0,
//             usdtMoeReserve1
//         );
//         uint256 moeAmount = _moeMerchantSwap(
//             address(USDT),
//             address(MOE),
//             usdtAmount,
//             (amountMoeOut * STANDARD_SLIPPAGE) / MAX_BPS
//         );

//         uint256 moeWmntReserve0 = LOCUS_DATA_FEED.parseUint256FromFeed(
//             address(this),
//             uint256(ReservedTopics.RESERVE_IN_MOE_WMNT_OF_MOE)
//         );
//         uint256 moeWmntReserve1 = LOCUS_DATA_FEED.parseUint256FromFeed(
//             address(this),
//             uint256(ReservedTopics.RESERVE_IN_MOE_WMNT_OF_WMNT)
//         );
//         (
//             uint256 lpMinted,
//             uint256 moeLeft,
//             uint256 wmntLeft
//         ) = _moeMerchantAddLiquidity(
//                 address(MOE),
//                 address(WMNT),
//                 moeAmount + moeTokensToAddToMoeLiquidity,
//                 wmntAmount + wmntTokensToAddToMoeLiquidity,
//                 moeWmntReserve0,
//                 moeWmntReserve1,
//                 STANDARD_SLIPPAGE
//             );
//         moeTokensToAddToMoeLiquidity = 0;
//         wmntTokensToAddToMoeLiquidity = 0;
//         if (moeLeft > 0) {
//             moeTokensToAddToMoeLiquidity = moeLeft;
//         }
//         if (wmntLeft > 0) {
//             wmntTokensToAddToMoeLiquidity = wmntLeft;
//         }
//         emit MintedMoeLp(oldLpBalance, balanceOfMoeLp());
//         uint256 circuitShares = balanceOfCircuitShares();
//         CIRCUIT_VAULT.deposit(lpMinted);
//         emit MintedCircuitShares(circuitShares, balanceOfCircuitShares());
//     }

//     function _burnShares(uint256 _shares) internal {
//         if (_shares == 0) return;
//         uint256 oldLpBalance = balanceOfMoeLp();
//         uint256 oldCircuitSharesBalance = balanceOfCircuitShares();
//         CIRCUIT_VAULT.withdraw(_shares);
//         emit BurnedCircuitShares(
//             oldCircuitSharesBalance,
//             balanceOfCircuitShares()
//         );
//         RemoveLiquidityData
//             memory removedLiquidityData = _moeMerchantRemoveLiquidity(
//                 address(MOE),
//                 address(WMNT),
//                 balanceOfMoeLp() - oldLpBalance
//             );
//         emit BurnedMoeLp(oldLpBalance, balanceOfMoeLp());

//         uint256 swappedFromWmntUsdcAmount = _agniSwap(
//             address(WMNT),
//             address(want),
//             removedLiquidityData.amountBWithdrawn,
//             STANDARD_SLIPPAGE
//         );

//         uint256 usdtMoeReserve0 = LOCUS_DATA_FEED.parseUint256FromFeed(
//             address(this),
//             uint256(ReservedTopics.RESERVE_IN_USDT_MOE_OF_USDT)
//         );
//         uint256 usdtMoeReserve1 = LOCUS_DATA_FEED.parseUint256FromFeed(
//             address(this),
//             uint256(ReservedTopics.RESERVE_IN_USDT_MOE_OF_MOE)
//         );
//         uint256 amountUsdtOut = MOE_ROUTER.getAmountOut(
//             removedLiquidityData.amountAWithdrawn,
//             usdtMoeReserve1,
//             usdtMoeReserve0
//         );
//         uint256 swappedFromMoeUsdtAmount = _moeMerchantSwap(
//             address(MOE),
//             address(USDT),
//             removedLiquidityData.amountAWithdrawn,
//             (amountUsdtOut * STANDARD_SLIPPAGE) / MAX_BPS
//         );

//         uint256 usdcUsdtReserve0 = LOCUS_DATA_FEED.parseUint256FromFeed(
//             address(this),
//             uint256(ReservedTopics.RESERVE_IN_USDC_USDT_OF_USDC)
//         );
//         uint256 usdcUsdtReserve1 = LOCUS_DATA_FEED.parseUint256FromFeed(
//             address(this),
//             uint256(ReservedTopics.RESERVE_IN_USDC_USDT_OF_USDT)
//         );
//         uint256 amountUsdcOut = MOE_ROUTER.getAmountOut(
//             swappedFromMoeUsdtAmount,
//             usdcUsdtReserve1,
//             usdcUsdtReserve0
//         );
//         uint256 swappedFromUsdtUsdcAmount = _moeMerchantSwap(
//             address(USDT),
//             address(want),
//             swappedFromMoeUsdtAmount,
//             (amountUsdcOut * STANDARD_SLIPPAGE) / MAX_BPS
//         );
//         emit WantTokensGathered(
//             swappedFromWmntUsdcAmount + swappedFromUsdtUsdcAmount
//         );
//     }

//     function liquidateAllPositions() internal override returns (uint256) {
//         _exitPosition(balanceOfCircuitShares());
//         return want.balanceOf(address(this));
//     }

//     function liquidatePosition(
//         uint256 _amountNeeded
//     ) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {
//         uint256 _wantBal = want.balanceOf(address(this));
//         if (_wantBal >= _amountNeeded) {
//             return (_amountNeeded, 0);
//         }

//         _withdrawSome(_amountNeeded - _wantBal);
//         _wantBal = want.balanceOf(address(this));

//         if (_amountNeeded > _wantBal) {
//             _liquidatedAmount = _wantBal;
//             _loss = _amountNeeded - _wantBal;
//         } else {
//             _liquidatedAmount = _amountNeeded;
//         }
//     }

//     function prepareMigration(address _newStrategy) internal override {
//         uint256 wantBalance = balanceOfWant();
//         if (wantBalance > 0) {
//             _mintShares(wantBalance);
//         }
//         IERC20(address(CIRCUIT_VAULT)).safeTransfer(
//             _newStrategy,
//             balanceOfCircuitShares()
//         );
//     }

//     function protectedTokens()
//         internal
//         pure
//         override
//         returns (address[] memory protected)
//     {
//         protected = new address[](5);
//         protected[0] = address(CIRCUIT_VAULT);
//         protected[1] = address(MOE);
//         protected[2] = address(USDT);
//         protected[3] = address(WMNT);
//         protected[4] = address(MOE_MERCHANT_MOE_WMNT_POOL);
//         return protected;
//     }

//     receive() external payable {}
// }
