// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./MoeMerchantLib.sol";
import "../../../integrations/circuit/ICircuitVault.sol";
import "../../../integrations/merchantMoe/IMoePair.sol";

library WmntMethStrategyLib {
    event MoePoolUnderlyingTokensRemains(
        uint256 indexed wmntAmountRemain,
        uint256 indexed methAmountRemain
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
        ICircuitVault(0xc37c7dEBa5E7F5dE572C914D5c159EA08DE1fefF);
    IERC20 public constant METH =
        IERC20(0xcDA86A272531e8640cD7F1a92c01839911B90bb0);
    IERC20 public constant MOE_MERCHANT_WMNT_METH_POOL =
        IERC20(0xa375ea3e1f92d62e3A71B668bAb09f7155267fa3);

    IERC20 public constant WMNT =
        IERC20(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8);
    IERC20 public constant USDT =
        IERC20(0x201EBa5CC46D216Ce6DC03F6a759e8E766e956aE);
    IERC20 public constant WETH =
        IERC20(0xdEAddEaDdeadDEadDEADDEAddEADDEAddead1111);

    uint256 public constant PRECISION = 1 ether;

    function updateTraces(
        address wantAddress,
        function(address, address) external update
    ) external {
        update(wantAddress, address(USDT));
        update(address(WMNT), address(METH));
        update(address(USDT), address(METH));
        update(address(USDT), address(WMNT));
    }

    function usdcToWmntSwap(
        address wantAddress,
        uint256 amountUsdc,
        uint256 slippageBps,
        function(address, uint256, address)
            external
            view
            returns (uint256) consult
    ) internal returns (uint256) {
        address[] memory toWmntPath = new address[](3);
        toWmntPath[0] = wantAddress;
        toWmntPath[1] = address(USDT);
        toWmntPath[2] = address(WMNT);
        return MoeMerchantLib.moeMerchantSwapMulti(
            toWmntPath,
            amountUsdc,
            slippageBps,
            consult
        );
    }

    function usdcToMethSwap(
        address wantAddress,
        uint256 amountUsdc,
        uint256 slippageBps,
        function(address, uint256, address)
            external
            view
            returns (uint256) consult
    ) internal returns (uint256) {
        address[] memory toMethPath = new address[](3);
        toMethPath[0] = wantAddress;
        toMethPath[1] = address(USDT);
        toMethPath[2] = address(METH);
        return MoeMerchantLib.moeMerchantSwapMulti(
            toMethPath,
            amountUsdc,
            slippageBps,
            consult
        );
    }

    function wmntToUsdcSwap(
        address wantAddress,
        uint256 amountWmnt,
        uint256 slippageBps,
        function(address, uint256, address)
            external
            view
            returns (uint256) consult
    ) internal returns (uint256) {
        address[] memory fromWmntPath = new address[](3);
        fromWmntPath[0] = address(WMNT);
        fromWmntPath[1] = address(USDT);
        fromWmntPath[2] = wantAddress;
        return MoeMerchantLib.moeMerchantSwapMulti(
            fromWmntPath,
            amountWmnt,
            slippageBps,
            consult
        );
    }

    function methToUsdcSwap(
        address wantAddress,
        uint256 amountMeth,
        uint256 slippageBps,
        function(address, uint256, address)
            external
            view
            returns (uint256) consult
    ) internal returns (uint256) {
        address[] memory fromMethPath = new address[](3);
        fromMethPath[0] = address(METH);
        fromMethPath[1] = address(USDT);
        fromMethPath[2] = wantAddress;
        return MoeMerchantLib.moeMerchantSwapMulti(
            fromMethPath,
            amountMeth,
            slippageBps,
            consult
        );

    }

    function usdcToWmntQuote(address wantAddress, uint256 amountUsdc) internal view returns (uint256) {
        if (amountUsdc == 0) return 0;
        address[] memory toWmntPath = new address[](3);
        toWmntPath[0] = wantAddress;
        toWmntPath[1] = address(USDT);
        toWmntPath[2] = address(WMNT);
        uint256[] memory toWmntSwapResult = MoeMerchantLib
            .MOE_ROUTER
            .getAmountsOut(amountUsdc, toWmntPath);
        return toWmntSwapResult[toWmntSwapResult.length - 1];
    }

    function wmntToUsdcQuote(address wantAddress, uint256 amountWmnt) internal view returns (uint256) {
        if (amountWmnt == 0) return 0;
        address[] memory fromWmntPath = new address[](3);
        fromWmntPath[0] = address(WMNT);
        fromWmntPath[1] = address(USDT);
        fromWmntPath[2] = wantAddress;
        uint256[] memory fromWmntSwapResult = MoeMerchantLib
            .MOE_ROUTER
            .getAmountsOut(amountWmnt, fromWmntPath);
        return fromWmntSwapResult[fromWmntSwapResult.length - 1];
    }

    function usdcToMethQuote(address wantAddress, uint256 amountUsdc) internal view returns (uint256) {
        if (amountUsdc == 0) return 0;
        address[] memory toMethPath = new address[](3);
        toMethPath[0] = wantAddress;
        toMethPath[1] = address(USDT);
        toMethPath[2] = address(METH);
        uint256[] memory toMethSwapResult = MoeMerchantLib
            .MOE_ROUTER
            .getAmountsOut(amountUsdc, toMethPath);
        return toMethSwapResult[toMethSwapResult.length - 1];
    }

    function methToUsdcQuote(address wantAddress, uint256 amountMeth) internal view returns (uint256) {
        if (amountMeth == 0) return 0;
        address[] memory fromMethPath = new address[](3);
        fromMethPath[0] = address(METH);
        fromMethPath[1] = address(USDT);
        fromMethPath[2] = wantAddress;
        uint256[] memory fromMethSwapResult = MoeMerchantLib
            .MOE_ROUTER
            .getAmountsOut(amountMeth, fromMethPath);
        return fromMethSwapResult[fromMethSwapResult.length - 1];
    }

    function _fromCircuitShares(uint256 shares) internal view returns (uint256 liquidity) {
        liquidity = (shares * CIRCUIT_VAULT.getPricePerFullShare()) / PRECISION;
    }

    function _toCircuitShares(uint256 liquidity) internal view returns (uint256 shares) {
        shares = (liquidity * PRECISION) / CIRCUIT_VAULT.getPricePerFullShare();
    }

    function wantToCircuitShares(
        address wantAddress,
        uint256 amount
    ) external view returns (uint256 result) {
        if (amount == 0) return 0;
        uint256 usdcForMethSwapAmount = amount / 2;
        uint256 usdcForWmntSwapAmount = amount - usdcForMethSwapAmount;

        uint256 methAmount = usdcToMethQuote(wantAddress, usdcForMethSwapAmount);
        uint256 wmntAmount = usdcToWmntQuote(wantAddress, usdcForWmntSwapAmount);

        IMoePair pair = IMoePair(address(MOE_MERCHANT_WMNT_METH_POOL));
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 lpTotalSupply = pair.totalSupply();

        uint256 liquidity = Math.min(
            (wmntAmount * lpTotalSupply) / reserve0,
            (methAmount * lpTotalSupply) / reserve1
        );
        result = _toCircuitShares(liquidity);
    }

    function circuitSharesToWant(
        address wantAddress,
        uint256 amount
    ) external view returns (uint256 result) {
        if (amount == 0) return 0;
        uint256 liquidity = _fromCircuitShares(amount);
        IMoePair pair = IMoePair(address(MOE_MERCHANT_WMNT_METH_POOL));
        uint256 lpTotalSupply = pair.totalSupply();
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 wmntAmount = (liquidity * reserve0) / lpTotalSupply;
        uint256 methAmount = (liquidity * reserve1) / lpTotalSupply;

        result = wmntToUsdcQuote(wantAddress, wmntAmount);
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
    )
        external
    {
        if (amount == 0) return;
        uint256 oldLpBalance = MOE_MERCHANT_WMNT_METH_POOL.balanceOf(address(this));

        uint256 oldWmntBalance = WMNT.balanceOf(address(this));
        uint256 oldMethBalance = METH.balanceOf(address(this));

        uint256 usdcForMethSwapAmount = amount / 2;
        uint256 usdcForWmntSwapAmount = amount - usdcForMethSwapAmount;

        uint256 methAmount = usdcToMethSwap(wantAddress, usdcForMethSwapAmount, slippageBps, consult);
        uint256 wmntAmount = usdcToWmntSwap(wantAddress, usdcForWmntSwapAmount, slippageBps, consult);

        (uint256 lpMinted, uint256 wmntLeft, uint256 methLeft) = MoeMerchantLib
            .moeMerchantAddLiquidity(
                address(WMNT),
                address(METH),
                wmntAmount + oldWmntBalance,
                methAmount + oldMethBalance,
                slippageBps,
                consult
            );
        emit MoePoolUnderlyingTokensRemains(wmntLeft, methLeft);
        emit MintedMoeLp(oldLpBalance, MOE_MERCHANT_WMNT_METH_POOL.balanceOf(address(this)));
        uint256 circuitShares = CIRCUIT_VAULT.balanceOf(address(this));
        CIRCUIT_VAULT.deposit(lpMinted);
        emit MintedCircuitShares(circuitShares, CIRCUIT_VAULT.balanceOf(address(this)));
    }

    function burnShares(
        uint256 shares,
        address wantAddress,
        uint256 slippageBps,
        function(address, uint256, address)
            external
            view
            returns (uint256) consult
    ) 
        external
    {
        if (shares == 0) return;
        uint256 oldLpBalance = MOE_MERCHANT_WMNT_METH_POOL.balanceOf(address(this));
        uint256 oldCircuitSharesBalance = CIRCUIT_VAULT.balanceOf(address(this));

        uint256 oldWmntBalance = WMNT.balanceOf(address(this));
        uint256 oldMethBalance = METH.balanceOf(address(this));

        CIRCUIT_VAULT.withdraw(shares);
        emit BurnedCircuitShares(
            oldCircuitSharesBalance,
            CIRCUIT_VAULT.balanceOf(address(this))
        );
        
        (uint256 amountAWithdrawn, uint256 amountBWithdrawn) = MoeMerchantLib
            .moeMerchantRemoveLiquidity(
                address(WMNT),
                address(METH),
                MOE_MERCHANT_WMNT_METH_POOL.balanceOf(address(this)) - oldLpBalance
            );
        emit BurnedMoeLp(oldLpBalance, MOE_MERCHANT_WMNT_METH_POOL.balanceOf(address(this)));

        uint256 wmntToBeSwappedToUsdc = amountAWithdrawn + oldWmntBalance;
        uint256 swappedFromWmntUsdcAmount = wmntToUsdcSwap(wantAddress, wmntToBeSwappedToUsdc, slippageBps, consult);

        uint256 methToBeSwappedToUsdc = amountBWithdrawn + oldMethBalance;
        uint256 swappedFromMethUsdcAmount = methToUsdcSwap(wantAddress, methToBeSwappedToUsdc, slippageBps, consult);

        emit WantTokensGathered(
            swappedFromWmntUsdcAmount + swappedFromMethUsdcAmount
        );
    }
}
