// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./MoeMerchantLib.sol";
import "../../../integrations/circuit/ICircuitVault.sol";
import "../../../integrations/merchantMoe/IMoePair.sol";

library MethWethStrategyLib {
    event MoePoolUnderlyingTokensRemains(
        uint256 indexed methAmountRemain,
        uint256 indexed wethAmountRemain
    );
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

    ICircuitVault public constant CIRCUIT_VAULT =
        ICircuitVault(0x16FA0C5f3eA649259C02c075dbA1C31fc66ea4E0);

    IERC20 public constant WETH =
        IERC20(0xdEAddEaDdeadDEadDEADDEAddEADDEAddead1111);
    IERC20 public constant METH =
        IERC20(0xcDA86A272531e8640cD7F1a92c01839911B90bb0);

    IERC20 public constant MOE_MERCHANT_METH_WETH_POOL =
        IERC20(0x86e3a987187feD135D6d9C114f1857D8144F01e1);

    function updateTraces(
        address wantAddress,
        function(address, address) external update
    ) external {
        update(wantAddress, address(METH));
        update(address(METH), address(WETH));
    }

    function usdcToMethQuote(
        address wantAddress,
        uint256 amountUsdc
    ) internal view returns (uint256) {
        address[] memory toMethPath = new address[](2);
        toMethPath[0] = wantAddress;
        toMethPath[1] = address(METH);
        return
            MoeMerchantLib.MOE_ROUTER.getAmountsOut(amountUsdc, toMethPath)[1];
    }

    function usdcToWethQuote(
        address wantAddress,
        uint256 amountWeth
    ) internal view returns (uint256) {
        address[] memory toWethPath = new address[](3);
        toWethPath[0] = wantAddress;
        toWethPath[1] = address(METH);
        toWethPath[2] = address(WETH);
        uint256[] memory toWethSwapResults = MoeMerchantLib
            .MOE_ROUTER
            .getAmountsOut(amountWeth, toWethPath);
        return toWethSwapResults[toWethSwapResults.length - 1];
    }

    function methToUsdcQuote(
        address wantAddress,
        uint256 amountMeth
    ) internal view returns (uint256) {
        address[] memory fromMethPath = new address[](2);
        fromMethPath[0] = address(METH);
        fromMethPath[1] = wantAddress;
        return
            MoeMerchantLib.MOE_ROUTER.getAmountsOut(amountMeth, fromMethPath)[
                1
            ];
    }

    function wethToUsdcQuote(
        address wantAddress,
        uint256 amountWeth
    ) internal view returns (uint256) {
        address[] memory fromWethPath = new address[](3);
        fromWethPath[0] = address(WETH);
        fromWethPath[1] = address(METH);
        fromWethPath[2] = wantAddress;
        uint256[] memory fromWethSwapResult = MoeMerchantLib
            .MOE_ROUTER
            .getAmountsOut(amountWeth, fromWethPath);
        return fromWethSwapResult[fromWethSwapResult.length - 1];
    }

    function wantToCircuitShares(
        uint256 amount,
        address wantAddress
    ) public view returns (uint256 result) {
        if (amount == 0) return 0;
        uint256 usdcForMethSwapAmount = amount / 2;
        uint256 usdcForWethSwapAmount = amount - usdcForMethSwapAmount;

        uint256 wethAmount = usdcToWethQuote(
            wantAddress,
            usdcForWethSwapAmount
        );
        uint256 methAmount = usdcToMethQuote(
            wantAddress,
            usdcForMethSwapAmount
        );

        IMoePair pair = IMoePair(address(MOE_MERCHANT_METH_WETH_POOL));
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 lpTotalSupply = pair.totalSupply();

        uint256 liquidity = Math.min(
            (methAmount * lpTotalSupply) / reserve0,
            (wethAmount * lpTotalSupply) / reserve1
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
        IMoePair pair = IMoePair(address(MOE_MERCHANT_METH_WETH_POOL));
        uint256 lpTotalSupply = pair.totalSupply();
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 methAmount = (liquidity * reserve0) / lpTotalSupply;
        uint256 wethAmount = (liquidity * reserve1) / lpTotalSupply;
        result += wethToUsdcQuote(wantAddress, wethAmount);
        result += methToUsdcQuote(wantAddress, methAmount);
    }

    function mintShares(
        uint256 amount,
        address wantAddress,
        uint256 slippageBps,
        function(address, uint256, address)
            external
            view
            returns (uint256) consult
    ) external {
        if (amount == 0) return;
        uint256 oldLpBalance = MOE_MERCHANT_METH_WETH_POOL.balanceOf(
            address(this)
        );

        uint256 usdcForWethSwapAmount = amount / 2;
        uint256 usdcForMethSwapAmount = amount - usdcForWethSwapAmount;

        uint256 oldMethBalance = METH.balanceOf(address(this));
        uint256 oldWethBalance = WETH.balanceOf(address(this));

        address[] memory toWethPath = new address[](3);
        toWethPath[0] = wantAddress;
        toWethPath[1] = address(METH);
        toWethPath[2] = address(WETH);
        uint256 wethAmount = MoeMerchantLib.moeMerchantSwapMulti(
            toWethPath,
            usdcForWethSwapAmount,
            slippageBps,
            consult
        );

        uint256 methAmount = MoeMerchantLib.moeMerchantSwapSingle(
            wantAddress,
            address(METH),
            usdcForMethSwapAmount,
            slippageBps,
            consult
        );

        (uint256 lpMinted, uint256 methLeft, uint256 wethLeft) = MoeMerchantLib
            .moeMerchantAddLiquidity(
                address(METH),
                address(WETH),
                methAmount + oldMethBalance,
                wethAmount + oldWethBalance,
                slippageBps,
                consult
            );
        emit MoePoolUnderlyingTokensRemains(methLeft, wethLeft);
        emit MintedMoeLp(
            oldLpBalance,
            MOE_MERCHANT_METH_WETH_POOL.balanceOf(address(this))
        );
        uint256 circuitShares = CIRCUIT_VAULT.balanceOf(address(this));
        CIRCUIT_VAULT.deposit(lpMinted);
        emit MintedCircuitShares(
            circuitShares,
            CIRCUIT_VAULT.balanceOf(address(this))
        );
    }

    function burnShares(
        uint256 shares,
        address wantAddress,
        uint256 slippageBps,
        function(address, uint256, address)
            external
            view
            returns (uint256) consult
    ) external {
        if (shares == 0) return;
        uint256 oldLpBalance = MOE_MERCHANT_METH_WETH_POOL.balanceOf(
            address(this)
        );
        uint256 oldCircuitSharesBalance = CIRCUIT_VAULT.balanceOf(
            address(this)
        );

        uint256 oldMethBalance = METH.balanceOf(address(this));
        uint256 oldWethBalance = WETH.balanceOf(address(this));

        CIRCUIT_VAULT.withdraw(shares);
        emit BurnedCircuitShares(
            oldCircuitSharesBalance,
            CIRCUIT_VAULT.balanceOf(address(this))
        );
        (uint256 amountAWithdrawn, uint256 amountBWithdrawn) = MoeMerchantLib
            .moeMerchantRemoveLiquidity(
                address(METH),
                address(WETH),
                MOE_MERCHANT_METH_WETH_POOL.balanceOf(address(this)) -
                    oldLpBalance
            );
        emit BurnedMoeLp(
            oldLpBalance,
            MOE_MERCHANT_METH_WETH_POOL.balanceOf(address(this))
        );

        address[] memory fromWethPath = new address[](3);
        fromWethPath[0] = address(WETH);
        fromWethPath[1] = address(METH);
        fromWethPath[2] = wantAddress;
        uint256 wethToBeSwappedToUsdc = amountBWithdrawn + oldWethBalance;
        uint256 swappedFromWethUsdcAmount = MoeMerchantLib.moeMerchantSwapMulti(
            fromWethPath,
            wethToBeSwappedToUsdc,
            slippageBps,
            consult
        );

        uint256 methToBeSwappedToUsdc = amountAWithdrawn + oldMethBalance;
        uint256 swappedFromMethUsdcAmount = MoeMerchantLib
            .moeMerchantSwapSingle(
                address(METH),
                wantAddress,
                methToBeSwappedToUsdc,
                slippageBps,
                consult
            );
        emit WantTokensGathered(
            swappedFromWethUsdcAmount + swappedFromMethUsdcAmount
        );
    }
}
