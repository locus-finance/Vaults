// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./AgniSwapLib.sol";
import "./MoeMerchantLib.sol";
import "../../../integrations/circuit/ICircuitVault.sol";
import "../../../integrations/merchantMoe/IMoePair.sol";

library WmntMethStrategyLib {
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

    uint256 public constant STANDARD_SLIPPAGE = 9000;
    uint256 public constant MAX_BPS = 10000;

    ICircuitVault public constant CIRCUIT_VAULT =
        ICircuitVault(0xc37c7dEBa5E7F5dE572C914D5c159EA08DE1fefF);
    IERC20 public constant WMNT =
        IERC20(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8);
    IERC20 public constant METH =
        IERC20(0xcDA86A272531e8640cD7F1a92c01839911B90bb0);
    IERC20 public constant MOE_MERCHANT_WMNT_METH_POOL =
        IERC20(0xa375ea3e1f92d62e3A71B668bAb09f7155267fa3);

    function wantToCircuitShares(
        address wantAddress,
        uint256 amount
    ) internal view returns (uint256 result) {
        if (amount == 0) return 0;
        uint256 usdcForMethSwapAmount = amount / 2;
        uint256 usdcForWmntSwapAmount = amount - usdcForMethSwapAmount;
        uint256 methAmount = AgniSwapLib.agniQuote(
            wantAddress,
            address(METH),
            usdcForMethSwapAmount
        );
        uint256 wmntAmount = AgniSwapLib.agniQuote(
            wantAddress,
            address(WMNT),
            usdcForWmntSwapAmount
        );
        IMoePair pair = IMoePair(address(MOE_MERCHANT_WMNT_METH_POOL));
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
        address wantAddress,
        uint256 amount
    ) internal view returns (uint256 result) {
        if (amount == 0) return 0;
        uint256 liquidity = (amount * CIRCUIT_VAULT.balance()) /
            CIRCUIT_VAULT.totalSupply();
        IMoePair pair = IMoePair(address(MOE_MERCHANT_WMNT_METH_POOL));
        uint256 lpTotalSupply = pair.totalSupply();
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 wmntAmount = (liquidity * reserve0) / lpTotalSupply;
        uint256 methAmount = (liquidity * reserve1) / lpTotalSupply;
        result =
            AgniSwapLib.agniQuote(
                address(METH),
                address(wantAddress),
                methAmount
            ) +
            AgniSwapLib.agniQuote(
                address(WMNT),
                address(wantAddress),
                wmntAmount
            );
    }

    function mintShares(
        uint256 _amount,
        address wantAddress,
        uint256 methTokensToAddToMoeLiquidity,
        uint256 wmntTokensToAddToMoeLiquidity
    )
        internal
        returns (
            uint256 resultingMethTokensToAddToMoeLiquidity,
            uint256 resultingWmntTokensToAddToMoeLiquidity
        )
    {
        if (_amount == 0) return;
        uint256 oldLpBalance = balanceOfMoeLp();

        uint256 usdcForMethSwapAmount = _amount / 2;
        uint256 usdcForWmntSwapAmount = _amount - usdcForMethSwapAmount;

        uint256 methAmount = AgniSwapLib.agniSwap(
            wantAddress,
            address(WmntMethStrategyLib.METH),
            usdcForMethSwapAmount,
            WmntMethStrategyLib.STANDARD_SLIPPAGE
        );
        uint256 wmntAmount = AgniSwapLib.agniSwap(
            wantAddress,
            address(WmntMethStrategyLib.WMNT),
            usdcForWmntSwapAmount,
            WmntMethStrategyLib.STANDARD_SLIPPAGE
        );
        (uint256 lpMinted, uint256 wmntLeft, uint256 methLeft) = MoeMerchantLib
            .moeMerchantAddLiquidity(
                address(WmntMethStrategyLib.WMNT),
                address(WmntMethStrategyLib.METH),
                methAmount + methTokensToAddToMoeLiquidity,
                wmntAmount + wmntTokensToAddToMoeLiquidity,
                WmntMethStrategyLib.STANDARD_SLIPPAGE
            );
        if (methLeft > 0) {
            resultingMethTokensToAddToMoeLiquidity = methLeft;
        }
        if (wmntLeft > 0) {
            resultingWmntTokensToAddToMoeLiquidity = wmntLeft;
        }
        emit WmntMethStrategyLib.MintedMoeLp(oldLpBalance, balanceOfMoeLp());
        uint256 circuitShares = balanceOfCircuitShares();
        WmntMethStrategyLib.CIRCUIT_VAULT.deposit(lpMinted);
        emit WmntMethStrategyLib.MintedCircuitShares(
            circuitShares,
            balanceOfCircuitShares()
        );
    }

    function burnShares(uint256 _shares, address wantAddress) internal {
        if (_shares == 0) return;
        uint256 oldLpBalance = balanceOfMoeLp();
        uint256 oldCircuitSharesBalance = balanceOfCircuitShares();
        WmntMethStrategyLib.CIRCUIT_VAULT.withdraw(_shares);
        emit WmntMethStrategyLib.BurnedCircuitShares(
            oldCircuitSharesBalance,
            balanceOfCircuitShares()
        );
        (uint256 amountAWithdrawn, uint256 amountBWithdrawn) = MoeMerchantLib
            .moeMerchantRemoveLiquidity(
                address(WmntMethStrategyLib.WMNT),
                address(WmntMethStrategyLib.METH),
                balanceOfMoeLp() - oldLpBalance
            );
        emit WmntMethStrategyLib.BurnedMoeLp(oldLpBalance, balanceOfMoeLp());

        uint256 swappedFromWmntUsdcAmount = AgniSwapLib.agniSwap(
            address(WmntMethStrategyLib.WMNT),
            wantAddress,
            amountAWithdrawn,
            WmntMethStrategyLib.STANDARD_SLIPPAGE
        );
        uint256 swappedFromMethhUsdcAmount = AgniSwapLib.agniSwap(
            address(WmntMethStrategyLib.METH),
            wantAddress,
            amountBWithdrawn,
            WmntMethStrategyLib.STANDARD_SLIPPAGE
        );

        emit WmntMethStrategyLib.WantTokensGathered(
            swappedFromWmntUsdcAmount + swappedFromMethhUsdcAmount
        );
    }
}
