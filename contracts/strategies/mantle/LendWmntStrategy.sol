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

// contract LendWmntStrategy is
//     BaseStrategyForSeparatedVault,
//     MoeMerchantStrategyHelper,
//     AgniStrategyHelper,
//     ILocusDataFeedUser
// {
//     using SafeERC20 for IERC20;
//     using Math for uint256;

//     enum ReservedTopics {
//         RESERVE_IN_LEND_WMNT_OF_LEND,
//         RESERVE_IN_LEND_WMNT_OF_WMNT,
//         RESERVE_IN_USDC_LEND_OF_USDC,
//         RESERVE_IN_USDC_LEND_OF_LEND
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
//         ICircuitVault(0x6CeaC8F90B7cAA311E025480503Bb0020B66f22A);

//     IERC20 public constant LEND =
//         IERC20(0x25356aeca4210eF7553140edb9b8026089E49396);
//     IERC20 public constant WMNT =
//         IERC20(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8);
//     IERC20 public constant MOE_MERCHANT_LEND_WMNT_POOL =
//         IERC20(0x30ac02b4c99D140CDE2a212ca807CBdA35D4f6b5);

//     uint256 public lendTokensToAddToMoeLiquidity;
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
//         WMNT.forceApprove(address(MOE_ROUTER), type(uint256).max);
//         LEND.forceApprove(address(MOE_ROUTER), type(uint256).max);
//         want.forceApprove(address(AGNI_SWAP_ROUTER), type(uint256).max);
//         WMNT.forceApprove(address(AGNI_SWAP_ROUTER), type(uint256).max);
//         LEND.forceApprove(address(AGNI_SWAP_ROUTER), type(uint256).max);
//         MOE_MERCHANT_LEND_WMNT_POOL.forceApprove(
//             address(MOE_ROUTER),
//             type(uint256).max
//         );
//         MOE_MERCHANT_LEND_WMNT_POOL.forceApprove(
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
//         IMoePair lendWmntPair = IMoePair(
//             MOE_FACTORY.getPair(address(LEND), address(WMNT))
//         );
//         IMoePair usdcLendPair = IMoePair(
//             MOE_FACTORY.getPair(address(want), address(LEND))
//         );
//         (uint112 lendWmntReserve0, uint256 lendWmntReserve1, ) = lendWmntPair
//             .getReserves();
//         (uint112 usdcLendReserve0, uint256 usdcLendReserve1, ) = usdcLendPair
//             .getReserves();

//         if (
//             topicNumber == uint256(ReservedTopics.RESERVE_IN_LEND_WMNT_OF_LEND)
//         ) {
//             result = bytes32(uint256(lendWmntReserve0));
//         } else if (
//             topicNumber == uint256(ReservedTopics.RESERVE_IN_LEND_WMNT_OF_WMNT)
//         ) {
//             result = bytes32(uint256(lendWmntReserve1));
//         } else if (
//             topicNumber == uint256(ReservedTopics.RESERVE_IN_USDC_LEND_OF_USDC)
//         ) {
//             result = bytes32(uint256(usdcLendReserve0));
//         } else if (
//             topicNumber == uint256(ReservedTopics.RESERVE_IN_USDC_LEND_OF_LEND)
//         ) {
//             result = bytes32(uint256(usdcLendReserve1));
//         } else {
//             revert UnknownTopicNumber(topicNumber);
//         }
//     }

//     function name() external pure override returns (string memory) {
//         return "LEND-WMNT Strategy";
//     }

//     function balanceOfWant() public view returns (uint256) {
//         return want.balanceOf(address(this));
//     }

//     function balanceOfLend() public view returns (uint256) {
//         return LEND.balanceOf(address(this));
//     }

//     function balanceOfWmnt() public view returns (uint256) {
//         return WMNT.balanceOf(address(this));
//     }

//     function balanceOfCircuitShares() public view returns (uint256) {
//         return CIRCUIT_VAULT.balanceOf(address(this));
//     }

//     function balanceOfMoeLp() public view returns (uint256) {
//         return MOE_MERCHANT_LEND_WMNT_POOL.balanceOf(address(this));
//     }

//     function wantToCircuitShares(
//         uint256 amount
//     ) public view returns (uint256 result) {
//         if (amount == 0) return 0;
//         uint256 usdcForLendSwapAmount = amount / 2;
//         uint256 usdcForWmntSwapAmount = amount - usdcForLendSwapAmount;

//         uint256 wmntAmount = _agniQuote(
//             address(want),
//             address(WMNT),
//             usdcForWmntSwapAmount
//         );

//         address[] memory path = new address[](2);
//         path[0] = address(want);
//         path[1] = address(LEND);
//         IMoePair pair = IMoePair(
//             MOE_FACTORY.getPair(address(want), address(LEND))
//         );
//         (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
//         uint256 lendAmount = MOE_ROUTER.getAmountsOut(
//             usdcForLendSwapAmount,
//             path
//         )[1];

//         path[0] = address(LEND);
//         path[1] = address(WMNT);
//         pair = IMoePair(MOE_FACTORY.getPair(address(LEND), address(WMNT)));
//         (reserve0, reserve1, ) = pair.getReserves();
//         uint256 lpTotalSupply = pair.totalSupply();
//         uint256 liquidity = Math.min(
//             (wmntAmount * lpTotalSupply) / reserve0,
//             (lendAmount * lpTotalSupply) / reserve1
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
//             MOE_FACTORY.getPair(address(LEND), address(WMNT))
//         );
//         uint256 lpTotalSupply = pair.totalSupply();
//         (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
//         uint256 lendAmount = (liquidity * reserve0) / lpTotalSupply;
//         uint256 wmntAmount = (liquidity * reserve1) / lpTotalSupply;
//         result = _agniQuote(address(WMNT), address(want), wmntAmount);
//         address[] memory path = new address[](2);
//         path[0] = address(LEND);
//         path[1] = address(want);
//         result += MOE_ROUTER.getAmountsOut(lendAmount, path)[1];
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

//         uint256 usdcForLendSwapAmount = _amount / 2;
//         uint256 usdcForWmntSwapAmount = _amount - usdcForLendSwapAmount;

//         uint256 wmntAmount = _agniSwap(
//             address(want),
//             address(WMNT),
//             usdcForWmntSwapAmount,
//             STANDARD_SLIPPAGE
//         );

//         uint256 usdcLendReserve0 = LOCUS_DATA_FEED.parseUint256FromFeed(
//             address(this),
//             uint256(ReservedTopics.RESERVE_IN_USDC_LEND_OF_USDC)
//         );
//         uint256 usdcLendReserve1 = LOCUS_DATA_FEED.parseUint256FromFeed(
//             address(this),
//             uint256(ReservedTopics.RESERVE_IN_USDC_LEND_OF_LEND)
//         );
//         uint256 amountUsdcOut = MOE_ROUTER.getAmountOut(
//             usdcForLendSwapAmount,
//             usdcLendReserve0,
//             usdcLendReserve1
//         );
//         uint256 lendAmount = _moeMerchantSwap(
//             address(want),
//             address(LEND),
//             usdcForLendSwapAmount,
//             (amountUsdcOut * STANDARD_SLIPPAGE) / MAX_BPS
//         );

//         uint256 lendWmntReserve0 = LOCUS_DATA_FEED.parseUint256FromFeed(
//             address(this),
//             uint256(ReservedTopics.RESERVE_IN_LEND_WMNT_OF_LEND)
//         );
//         uint256 lendWmntReserve1 = LOCUS_DATA_FEED.parseUint256FromFeed(
//             address(this),
//             uint256(ReservedTopics.RESERVE_IN_LEND_WMNT_OF_WMNT)
//         );

//         (
//             uint256 lpMinted,
//             uint256 lendLeft,
//             uint256 wmntLeft
//         ) = _moeMerchantAddLiquidity(
//                 address(LEND),
//                 address(WMNT),
//                 lendAmount + lendTokensToAddToMoeLiquidity,
//                 wmntAmount + wmntTokensToAddToMoeLiquidity,
//                 lendWmntReserve0,
//                 lendWmntReserve1,
//                 STANDARD_SLIPPAGE
//             );
//         lendTokensToAddToMoeLiquidity = 0;
//         wmntTokensToAddToMoeLiquidity = 0;
//         if (lendLeft > 0) {
//             lendTokensToAddToMoeLiquidity = lendLeft;
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
//                 address(LEND),
//                 address(WMNT),
//                 balanceOfMoeLp() - oldLpBalance
//             );
//         emit BurnedMoeLp(oldLpBalance, balanceOfMoeLp());
//         uint256 usdcLendReserve0 = LOCUS_DATA_FEED.parseUint256FromFeed(
//             address(this),
//             uint256(ReservedTopics.RESERVE_IN_USDC_LEND_OF_USDC)
//         );
//         uint256 usdcLendReserve1 = LOCUS_DATA_FEED.parseUint256FromFeed(
//             address(this),
//             uint256(ReservedTopics.RESERVE_IN_USDC_LEND_OF_LEND)
//         );
//         uint256 amountUsdcOut = MOE_ROUTER.getAmountOut(
//             removedLiquidityData.amountAWithdrawn,
//             usdcLendReserve1,
//             usdcLendReserve0
//         );
//         uint256 swappedFromLendUsdcAmount = _moeMerchantSwap(
//             address(LEND),
//             address(want),
//             removedLiquidityData.amountAWithdrawn,
//             (amountUsdcOut * STANDARD_SLIPPAGE) / MAX_BPS
//         );
//         uint256 swappedFromWmntUsdcAmount = _agniSwap(
//             address(WMNT),
//             address(want),
//             removedLiquidityData.amountBWithdrawn,
//             STANDARD_SLIPPAGE
//         );
//         emit WantTokensGathered(
//             swappedFromLendUsdcAmount + swappedFromWmntUsdcAmount
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
//         protected = new address[](4);
//         protected[0] = address(CIRCUIT_VAULT);
//         protected[1] = address(LEND);
//         protected[2] = address(WMNT);
//         protected[3] = address(MOE_MERCHANT_LEND_WMNT_POOL);
//         return protected;
//     }

//     receive() external payable {}
// }
