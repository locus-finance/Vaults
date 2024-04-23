// // SPDX-License-Identifier: AGPL-3.0

// pragma solidity ^0.8.18;

// import {BaseStrategy} from "@yearn-protocol/contracts/BaseStrategy.sol";
// import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
// import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// import "../../abstracts/BaseStrategyForSeparatedVault.sol";
// import "../../integrations/circuit/ICircuitVault.sol";
// import "../../utils/Utils.sol";
// import "../../abstracts/mantle/MoeMerchantStrategyHelper.sol";

// contract LentWmntStrategy is BaseStrategyForSeparatedVault, MoeMerchantStrategyHelper {
//     using SafeERC20 for IERC20;
//     using Math for uint256;

//     event MintedCircuitShares(uint256 indexed amount);
//     event MintedMoeLp(uint256 indexed amount);
//     event BurnedCircuitShares(uint256 indexed amount);
//     event BurnedMoeLp(uint256 indexed amount);
//     event WantTokenGathered(uint256 indexed amount);

//     ICircuitVault public constant CIRCUIT_VAULT =
//         ICircuitVault(0x6CeaC8F90B7cAA311E025480503Bb0020B66f22A);

//     IERC20 public constant LEND = IERC20(0x25356aeca4210eF7553140edb9b8026089E49396);
//     IERC20 public constant WMNT = IERC20(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8);
//     IERC20 public constant MOE_MERCHANT_LEND_WMNT_POOL = IERC20(0x30ac02b4c99d140cde2a212ca807cbda35d4f6b5);

//     uint256 public constant TOPICS_AMOUNT = uint256(type(ReservedTopics).max) + 1;

//     function initialize(address _vault, address _strategist) external {
//         __Base_Strategy_Initialize(_vault, _strategist, _strategist, _strategist);
//         want.approve(address(MOE_ROUTER), type(uint256).max);
//         LEND.approve(address(MOE_ROUTER), type(uint256).max);
//         WMNT.approve(address(MOE_ROUTER), type(uint256).max);
//         MOE_MERCHANT_LEND_WMNT_POOL.approve(
//             address(MOE_ROUTER),
//             type(uint256).max
//         );
//     }

//     function setUpLocusDataFeedReserveTokensTopics() external {
//         LOCUS_DATA_FEED.setFeed(TOPICS_AMOUNT);
//         // LOCUS_DATA_FEED.setValue(
//         //     uint256(ReservedTopics.TOKEN_A),
//         //     bytes32(uint256(uint160(address(want))))
//         // );
//         // LOCUS_DATA_FEED.setValue(
//         //     uint256(ReservedTopics.TOKEN_B),
//         //     bytes32(uint256(uint160(address(USDY))))
//         // );
//         LOCUS_DATA_FEED.updateFeed(address(this));
//     }

//     function name() external pure override returns (string memory) {
//         return "LEND-WMNT Strategy";
//     }

//     function balanceOfWant() public view returns (uint256) {
//         return want.balanceOf(address(this));
//     }

//     function balanceOfCircuitShares() public view returns (uint256) {
//         return CIRCUIT_VAULT.balanceOf(address(this));
//     }

//     function balanceOfMoeLp() public view returns (uint256) {
//         // return MOE_MERCHANT_USDC_USDY_POOL.balanceOf(address(this));
//     }

//     function _wantToCircuitShares(
//         uint256 amount
//     ) internal view returns (uint256 result) {
//         address[] memory path = new address[](2);
//         path[0] = address(want);
//         path[1] = address(USDY);
//         uint256 amountAToAdd = amount / 2;
//         uint256 amountAToSwapToB = amount - amountAToAdd;
//         IMoePair pair = IMoePair(
//             MOE_FACTORY.getPair(address(want), address(USDY))
//         );
//         (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
//         uint256 amountBToAdd = MOE_ROUTER.getAmountsOut(amountAToSwapToB, path)[
//             0
//         ];
//         uint256 lpTotalSupply = pair.totalSupply();
//         uint256 liquidity = Math.min(
//             (amountAToAdd * lpTotalSupply) / reserve0,
//             (amountBToAdd * lpTotalSupply) / reserve1
//         );
//         result = CIRCUIT_VAULT.getPricePerFullShare() * liquidity;
//     }

//     function _circuitSharesToWant(
//         uint256 amount
//     ) internal view returns (uint256 result) {
//         uint256 liquidity = amount / CIRCUIT_VAULT.getPricePerFullShare();
//         IMoePair pair = IMoePair(
//             MOE_FACTORY.getPair(address(want), address(USDY))
//         );
//         uint256 lpTotalSupply = pair.totalSupply();
//         (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
//         result = (liquidity * reserve0) / lpTotalSupply;
//         uint256 usdyAmount = (liquidity * reserve1) / lpTotalSupply;
//         address[] memory path = new address[](2);
//         path[0] = address(USDY);
//         path[1] = address(want);
//         result += MOE_ROUTER.getAmountsOut(usdyAmount, path)[0];
//     }

//     function _withdrawSome(uint256 _amountNeeded) internal {
//         if (_amountNeeded == 0) {
//             return;
//         }
//         uint256 sharesToWithdraw = Math.min(
//             _wantToCircuitShares(_amountNeeded),
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
//         _wants += _circuitSharesToWant(balanceOfCircuitShares());
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
//         uint256 lpMinted = _moeMerchantAddLiquidity(address(want), address(USDY), _amount);
//         emit MintedMoeLp(lpMinted);
//         uint256 circuitShares = balanceOfCircuitShares();
//         CIRCUIT_VAULT.deposit(lpMinted);
//         circuitShares = balanceOfCircuitShares() - circuitShares;
//         emit MintedCircuitShares(circuitShares);
//     }

//     function _burnShares(uint256 _shares) internal {
//         if (_shares == 0) return;
//         uint256 lpTokens = balanceOfMoeLp();
//         CIRCUIT_VAULT.withdraw(_shares);
//         lpTokens = balanceOfMoeLp() - lpTokens;
//         emit BurnedCircuitShares(_shares);
//         RemoveLiquidityData memory removedLiquidityData = _moeMerchantRemoveLiquidity(
//             address(want),
//             address(USDY),
//             lpTokens
//         );
//         emit BurnedMoeLp(lpTokens);
//         uint256 reserve0 = LOCUS_DATA_FEED.parseUint256FromFeed(address(this), uint256(ReservedTopics.RESERVE_A));
//         uint256 reserve1 = LOCUS_DATA_FEED.parseUint256FromFeed(address(this), uint256(ReservedTopics.RESERVE_B));
//         uint256 amountUsdcOut = MOE_ROUTER.getAmountOut(removedLiquidityData.amountBWithdrawn, reserve1, reserve0);
//         uint256 usdyToUsdcSwappedAmount = _moeMerchantSwap(
//             address(USDY),
//             address(want),
//             removedLiquidityData.amountBWithdrawn,
//             amountUsdcOut - ((amountUsdcOut * STANDARD_SLIPPAGE) / MAX_BPS)
//         );
//         emit WantTokenGathered(removedLiquidityData.amountAWithdrawn + usdyToUsdcSwappedAmount);
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
//     {}

//     receive() external payable {}
// }
