// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./AgniSwapLib.sol";
import "./MoeMerchantLib.sol";
import "../../../integrations/circuit/ICircuitVault.sol";
import "../../../integrations/merchantMoe/IMoePair.sol";

library MethWethStrategyLib {
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

    uint24 public constant STANDARD_AGNI_FEE_USDC_WETH = 100;

    ICircuitVault public constant CIRCUIT_VAULT =
        ICircuitVault(0x16FA0C5f3eA649259C02c075dbA1C31fc66ea4E0);

    IERC20 public constant WETH =
        IERC20(0xdEAddEaDdeadDEadDEADDEAddEADDEAddead1111);
    IERC20 public constant METH =
        IERC20(0xcDA86A272531e8640cD7F1a92c01839911B90bb0);
    IERC20 public constant MOE_MERCHANT_METH_WETH_POOL =
        IERC20(0x86e3a987187feD135D6d9C114f1857D8144F01e1);

    function wantToCircuitShares(
        uint256 amount,
        address wantAddress,
        uint32 agniTwapRangeSecs
    ) public view returns (uint256 result) {
        if (amount == 0) return 0;
        uint256 usdcForMethSwapAmount = amount / 2;
        uint256 usdcForWethSwapAmount = amount - usdcForMethSwapAmount;

        uint256 wethAmount = AgniSwapLib.agniQuote(
            wantAddress,
            address(WETH),
            usdcForWethSwapAmount,
            STANDARD_AGNI_FEE_USDC_WETH,
            agniTwapRangeSecs
        );

        address[] memory path = new address[](2);
        path[0] = wantAddress;
        path[1] = address(METH);
        IMoePair pair = IMoePair(
            MoeMerchantLib.MOE_FACTORY.getPair(wantAddress, address(METH))
        );
        uint256 methAmount = MoeMerchantLib.MOE_ROUTER.getAmountsOut(
            usdcForMethSwapAmount,
            path
        )[1];

        pair = IMoePair(MoeMerchantLib.MOE_FACTORY.getPair(address(METH), address(WETH)));
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
        uint256 amount,
        address wantAddress,
        uint32 agniTwapRangeSecs
    ) public view returns (uint256 result) {
        if (amount == 0) return 0;
        uint256 liquidity = (amount * CIRCUIT_VAULT.balance()) /
            CIRCUIT_VAULT.totalSupply();
        IMoePair pair = IMoePair(
            MoeMerchantLib.MOE_FACTORY.getPair(address(METH), address(WETH))
        );
        uint256 lpTotalSupply = pair.totalSupply();
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 methAmount = (liquidity * reserve0) / lpTotalSupply;
        uint256 wethAmount = (liquidity * reserve1) / lpTotalSupply;
        result = AgniSwapLib.agniQuote(address(WETH), wantAddress, wethAmount, STANDARD_AGNI_FEE_USDC_WETH, agniTwapRangeSecs);
        address[] memory path = new address[](2);
        path[0] = address(METH);
        path[1] = wantAddress;
        result += MoeMerchantLib.MOE_ROUTER.getAmountsOut(methAmount, path)[1];
    }

    function mintShares(
        uint256 amount,
        address wantAddress,
        uint256 methTokensToAddToMoeLiquidity,
        uint256 wethTokensToAddToMoeLiquidity,
        uint256 slippageBps,
        uint32 agniTwapRangeSecs,
        function() external view returns (uint256) balanceOfMoeLp,
        function() external view returns (uint256) balanceOfCircuitShares,
        function(address, uint256, address) external view returns(uint256) consult
    )
        external
        returns (
            uint256 resultingMethTokensToAddToMoeLiquidity,
            uint256 resultingWethTokensToAddToMoeLiquidity
        ) 
    {
        if (amount == 0) return (methTokensToAddToMoeLiquidity, wethTokensToAddToMoeLiquidity);
        uint256 oldLpBalance = balanceOfMoeLp();

        uint256 usdcForWethSwapAmount = amount / 2;
        uint256 usdcForMethSwapAmount = amount - usdcForWethSwapAmount;

        uint256 wethAmount = AgniSwapLib.agniSwap(
            wantAddress,
            address(WETH),
            usdcForWethSwapAmount,
            slippageBps,
            STANDARD_AGNI_FEE_USDC_WETH,
            agniTwapRangeSecs
        );

        uint256 methAmount = MoeMerchantLib.moeMerchantSwap(
            wantAddress,
            address(METH),
            usdcForMethSwapAmount,
            slippageBps,
            consult
        );

        (
            uint256 lpMinted,
            uint256 methLeft,
            uint256 wethLeft
        ) = MoeMerchantLib.moeMerchantAddLiquidity(
                address(METH),
                address(WETH),
                wethAmount + wethTokensToAddToMoeLiquidity,
                methAmount + methTokensToAddToMoeLiquidity,
                slippageBps,
                consult
            );
        if (wethLeft > 0) {
            resultingWethTokensToAddToMoeLiquidity = wethLeft;
        }
        if (methLeft > 0) {
            resultingMethTokensToAddToMoeLiquidity = methLeft;
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
                address(METH),
                address(WETH),
                balanceOfMoeLp() - oldLpBalance
            );
        emit BurnedMoeLp(oldLpBalance, balanceOfMoeLp());

        uint256 swappedFromWethUsdcAmount = AgniSwapLib.agniSwap(
            address(WETH),
            wantAddress,
            amountBWithdrawn,
            slippageBps,
            STANDARD_AGNI_FEE_USDC_WETH,
            agniTwapRangeSecs
        );

        uint256 swappedFromMethUsdcAmount = MoeMerchantLib.moeMerchantSwap(
            address(METH),
            wantAddress,
            amountAWithdrawn,
            slippageBps,
            consult
        );
        emit WantTokensGathered(
            swappedFromWethUsdcAmount + swappedFromMethUsdcAmount
        );
    }
}