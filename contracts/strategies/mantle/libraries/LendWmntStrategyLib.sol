// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./AgniSwapLib.sol";
import "./MoeMerchantLib.sol";
import "../../../integrations/circuit/ICircuitVault.sol";
import "../../../integrations/merchantMoe/IMoePair.sol";

library LendWmntStrategyLib {
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

    ICircuitVault public constant CIRCUIT_VAULT =
        ICircuitVault(0x6CeaC8F90B7cAA311E025480503Bb0020B66f22A);

    IERC20 public constant LEND =
        IERC20(0x25356aeca4210eF7553140edb9b8026089E49396);
    IERC20 public constant WMNT =
        IERC20(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8);
    IERC20 public constant MOE_MERCHANT_LEND_WMNT_POOL =
        IERC20(0x30ac02b4c99D140CDE2a212ca807CBdA35D4f6b5);

    function wantToCircuitShares(
        uint256 amount,
        address wantAddress
    ) external view returns (uint256 result) {
        if (amount == 0) return 0;
        uint256 usdcForLendSwapAmount = amount / 2;
        uint256 usdcForWmntSwapAmount = amount - usdcForLendSwapAmount;

        uint256 wmntAmount = AgniSwapLib.agniQuote(
            wantAddress,
            address(WMNT),
            usdcForWmntSwapAmount
        );

        address[] memory path = new address[](2);
        path[0] = wantAddress;
        path[1] = address(LEND);
        IMoePair pair = IMoePair(
            MoeMerchantLib.MOE_FACTORY.getPair(wantAddress, address(LEND))
        );
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 lendAmount = MoeMerchantLib.MOE_ROUTER.getAmountsOut(
            usdcForLendSwapAmount,
            path
        )[1];

        path[0] = address(LEND);
        path[1] = address(WMNT);
        pair = IMoePair(MoeMerchantLib.MOE_FACTORY.getPair(address(LEND), address(WMNT)));
        (reserve0, reserve1, ) = pair.getReserves();
        uint256 lpTotalSupply = pair.totalSupply();
        uint256 liquidity = Math.min(
            (wmntAmount * lpTotalSupply) / reserve0,
            (lendAmount * lpTotalSupply) / reserve1
        );
        result =
            (liquidity * CIRCUIT_VAULT.totalSupply()) /
            CIRCUIT_VAULT.balance();
    }

    function circuitSharesToWant(
        uint256 amount,
        address wantAddress
    ) public view returns (uint256 result) {
        if (amount == 0) return 0;
        uint256 liquidity = (amount * CIRCUIT_VAULT.balance()) /
            CIRCUIT_VAULT.totalSupply();
        IMoePair pair = IMoePair(
            MoeMerchantLib.MOE_FACTORY.getPair(address(LEND), address(WMNT))
        );
        uint256 lpTotalSupply = pair.totalSupply();
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 lendAmount = (liquidity * reserve0) / lpTotalSupply;
        uint256 wmntAmount = (liquidity * reserve1) / lpTotalSupply;
        result = AgniSwapLib.agniQuote(address(WMNT), wantAddress, wmntAmount);
        address[] memory path = new address[](2);
        path[0] = address(LEND);
        path[1] = wantAddress;
        result += MoeMerchantLib.MOE_ROUTER.getAmountsOut(lendAmount, path)[1];
    }

    function mintShares(
        uint256 amount,
        address wantAddress,
        uint256 lendTokensToAddToMoeLiquidity,
        uint256 wmntTokensToAddToMoeLiquidity,
        function() external view returns (uint256) balanceOfMoeLp,
        function() external view returns (uint256) balanceOfCircuitShares,
        function(address, uint256, address) external view returns(uint256) consult
    )
        external
        returns (
            uint256 resultingLendTokensToAddToMoeLiquidity,
            uint256 resultingWmntTokensToAddToMoeLiquidity
        ) 
    {
        if (amount == 0) return (lendTokensToAddToMoeLiquidity, wmntTokensToAddToMoeLiquidity);
        uint256 oldLpBalance = balanceOfMoeLp();

        uint256 usdcForLendSwapAmount = amount / 2;
        uint256 usdcForWmntSwapAmount = amount - usdcForLendSwapAmount;

        uint256 wmntAmount = AgniSwapLib.agniSwap(
            wantAddress,
            address(WMNT),
            usdcForWmntSwapAmount,
            STANDARD_SLIPPAGE
        );

        uint256 lendAmount = MoeMerchantLib.moeMerchantSwap(
            wantAddress,
            address(LEND),
            usdcForLendSwapAmount,
            STANDARD_SLIPPAGE,
            consult
        );

        (
            uint256 lpMinted,
            uint256 lendLeft,
            uint256 wmntLeft
        ) = MoeMerchantLib.moeMerchantAddLiquidity(
                address(LEND),
                address(WMNT),
                lendAmount + lendTokensToAddToMoeLiquidity,
                wmntAmount + wmntTokensToAddToMoeLiquidity,
                STANDARD_SLIPPAGE,
                consult
            );
        if (lendLeft > 0) {
            resultingLendTokensToAddToMoeLiquidity = lendLeft;
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
        function() external view returns (uint256) balanceOfMoeLp,
        function() external view returns (uint256) balanceOfCircuitShares,
        function(address, uint256, address) external view returns(uint256) consult
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
                address(LEND),
                address(WMNT),
                balanceOfMoeLp() - oldLpBalance
            );
        emit BurnedMoeLp(oldLpBalance, balanceOfMoeLp());

        uint256 swappedFromLendUsdcAmount = MoeMerchantLib.moeMerchantSwap(
            address(LEND),
            wantAddress,
            amountAWithdrawn,
            STANDARD_SLIPPAGE,
            consult
        );
        uint256 swappedFromWmntUsdcAmount = AgniSwapLib.agniSwap(
            address(WMNT),
            wantAddress,
            amountBWithdrawn,
            STANDARD_SLIPPAGE
        );
        emit WantTokensGathered(
            swappedFromLendUsdcAmount + swappedFromWmntUsdcAmount
        );
    }
}
