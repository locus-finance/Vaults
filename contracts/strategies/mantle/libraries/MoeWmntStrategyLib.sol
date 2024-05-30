// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./MoeMerchantLib.sol";
import "../../../integrations/circuit/ICircuitVault.sol";
import "../../../integrations/merchantMoe/IMoePair.sol";

library MoeWmntStrategyLib {
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

    uint24 public constant STANDARD_AGNI_FEE_USDC_USDT = 100;
    uint24 public constant STANDARD_AGNI_FEE_USDT_WETH = 500;
    uint24 public constant STANDARD_AGNI_FEE_WETH_WMNT = 500;

    ICircuitVault public constant CIRCUIT_VAULT =
        ICircuitVault(0xa3647389cf2bF9279ab239d3710bB8a2eFE0BC8B);

    IERC20 public constant USDT =
        IERC20(0x201EBa5CC46D216Ce6DC03F6a759e8E766e956aE);
    IERC20 public constant MOE =
        IERC20(0x4515A45337F461A11Ff0FE8aBF3c606AE5dC00c9);
    IERC20 public constant WMNT =
        IERC20(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8);
    IERC20 public constant WETH =
        IERC20(0xdEAddEaDdeadDEadDEADDEAddEADDEAddead1111);

    IERC20 public constant MOE_MERCHANT_MOE_WMNT_POOL =
        IERC20(0x763868612858358f62b05691dB82Ad35a9b3E110);

    function wantToCircuitShares(
        uint256 amount,
        address wantAddress,
        uint32 agniTwapRangeSecs,
        function(uint32, uint256) external view returns (uint256) usdcToWmntQuote
    ) external view returns (uint256 result) {
        if (amount == 0) return 0;
        uint256 usdcForUsdtSwapAmount = amount / 2;
        uint256 usdcForWmntSwapAmount = amount - usdcForUsdtSwapAmount;

        uint256 wmntAmount = usdcToWmntQuote(agniTwapRangeSecs, usdcForWmntSwapAmount);

        address[] memory path = new address[](2);
        path[0] = wantAddress;
        path[1] = address(USDT);
        IMoePair pair = IMoePair(
            MoeMerchantLib.MOE_FACTORY.getPair(wantAddress, address(USDT))
        );
        uint256 usdtAmount = MoeMerchantLib.MOE_ROUTER.getAmountsOut(
            usdcForUsdtSwapAmount,
            path
        )[1];

        path[0] = address(USDT);
        path[1] = address(MOE);
        uint256 moeAmount = MoeMerchantLib.MOE_ROUTER.getAmountsOut(usdtAmount, path)[1];

        pair = IMoePair(MoeMerchantLib.MOE_FACTORY.getPair(address(MOE), address(WMNT)));

        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 lpTotalSupply = pair.totalSupply();

        uint256 liquidity = Math.min(
            (wmntAmount * lpTotalSupply) / reserve0,
            (moeAmount * lpTotalSupply) / reserve1
        );

        result =
            (liquidity * CIRCUIT_VAULT.totalSupply()) /
            CIRCUIT_VAULT.balance();
    }

    function circuitSharesToWant(
        uint256 amount,
        address wantAddress,
        uint32 agniTwapRangeSecs,
        function(uint32, uint256) external view returns (uint256) wmntToUsdcQuote
    ) external view returns (uint256 result) {
        if (amount == 0) return 0;
        uint256 liquidity = (amount * CIRCUIT_VAULT.balance()) /
            CIRCUIT_VAULT.totalSupply();

        IMoePair pair = IMoePair(
            MoeMerchantLib.MOE_FACTORY.getPair(address(MOE), address(WMNT))
        );
        uint256 lpTotalSupply = pair.totalSupply();
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        uint256 moeAmount = (liquidity * reserve0) / lpTotalSupply;
        uint256 wmntAmount = (liquidity * reserve1) / lpTotalSupply;

        result = wmntToUsdcQuote(agniTwapRangeSecs, wmntAmount);

        address[] memory path = new address[](2);

        path[0] = address(MOE);
        path[1] = address(USDT);
        uint256 usdtAmount = MoeMerchantLib.MOE_ROUTER.getAmountsOut(moeAmount, path)[1];
        path[0] = address(USDT);
        path[1] = wantAddress;

        result += MoeMerchantLib.MOE_ROUTER.getAmountsOut(usdtAmount, path)[1];
    }

    function mintShares(
        uint256 amount,
        address wantAddress,
        uint256 moeTokensToAddToMoeLiquidity,
        uint256 wmntTokensToAddToMoeLiquidity,
        uint256 slippageBps,
        uint32 agniTwapRangeSecs,
        function() external view returns (uint256) balanceOfMoeLp,
        function() external view returns (uint256) balanceOfCircuitShares,
        function(address, uint256, address) external view returns(uint256) consult,
        function(uint32, uint256, uint256) external returns (uint256) usdcToWmntSwap
    )
        external
        returns (
            uint256 resultingMoeTokensToAddToMoeLiquidity,
            uint256 resultingWmntTokensToAddToMoeLiquidity
        ) 
    {
        if (amount == 0) return (moeTokensToAddToMoeLiquidity, wmntTokensToAddToMoeLiquidity);
        uint256 oldLpBalance = balanceOfMoeLp();

        uint256 usdcForUsdtSwapAmount = amount / 2;
        uint256 usdcForWmntSwapAmount = amount - usdcForUsdtSwapAmount;

        uint256 wmntAmount = usdcToWmntSwap(agniTwapRangeSecs, slippageBps, usdcForWmntSwapAmount);

        uint256 usdtAmount = MoeMerchantLib.moeMerchantSwapSingle(
            wantAddress,
            address(USDT),
            usdcForUsdtSwapAmount,
            slippageBps,
            consult
        );

        uint256 moeAmount = MoeMerchantLib.moeMerchantSwapSingle(
            address(USDT),
            address(MOE),
            usdtAmount,
            slippageBps,
            consult
        );

        (
            uint256 lpMinted,
            uint256 moeLeft,
            uint256 wmntLeft
        ) = MoeMerchantLib.moeMerchantAddLiquidity(
                address(MOE),
                address(WMNT),
                moeAmount + moeTokensToAddToMoeLiquidity,
                wmntAmount + wmntTokensToAddToMoeLiquidity,
                slippageBps,
                consult
            );
        if (moeLeft > 0) {
            resultingMoeTokensToAddToMoeLiquidity = moeLeft;
        }
        if (wmntLeft > 0) {
            resultingWmntTokensToAddToMoeLiquidity = wmntLeft;
        }
        emit MintedMoeLp(oldLpBalance, balanceOfMoeLp());
        uint256 circuitShares = balanceOfCircuitShares();
        CIRCUIT_VAULT.deposit(lpMinted);
        emit MintedCircuitShares(circuitShares, balanceOfCircuitShares());
    }

    function burnShares(
        uint256 shares, 
        address wantAddress,
        uint256 slippageBps,
        uint32 agniTwapRangeSecs,
        function() external view returns (uint256) balanceOfMoeLp,
        function() external view returns (uint256) balanceOfCircuitShares,
        function(address, uint256, address) external view returns(uint256) consult,
        function(uint32, uint256, uint256) external returns (uint256) wmntToUsdcSwap
    ) external {
        if (shares == 0) return;
        uint256 oldLpBalance = balanceOfMoeLp();
        uint256 oldCircuitSharesBalance = balanceOfCircuitShares();
        CIRCUIT_VAULT.withdraw(shares);
        emit BurnedCircuitShares(
            oldCircuitSharesBalance,
            balanceOfCircuitShares()
        );
        (uint256 amountAWithdrawn, uint256 amountBWithdrawn) = MoeMerchantLib.moeMerchantRemoveLiquidity(
                address(MOE),
                address(WMNT),
                balanceOfMoeLp() - oldLpBalance
            );
        emit BurnedMoeLp(oldLpBalance, balanceOfMoeLp());

        uint256 swappedFromWmntUsdcAmount = wmntToUsdcSwap(agniTwapRangeSecs, slippageBps, amountBWithdrawn);

        uint256 swappedFromMoeUsdtAmount = MoeMerchantLib.moeMerchantSwapSingle(
            address(MOE),
            address(USDT),
            amountAWithdrawn,
            slippageBps,
            consult
        );

        uint256 swappedFromUsdtUsdcAmount = MoeMerchantLib.moeMerchantSwapSingle(
            address(USDT),
            wantAddress,
            swappedFromMoeUsdtAmount,
            slippageBps,
            consult
        );
        emit WantTokensGathered(
            swappedFromWmntUsdcAmount + swappedFromUsdtUsdcAmount
        );
    }
}