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

    function updateTraces(
        address wantAddress,
        function(address, address) external update
    ) external {
        update(wantAddress, address(USDT));
        update(address(USDT), address(MOE));
        update(address(USDT), address(WMNT));
        update(address(MOE), address(WMNT));
    }

    function wantToCircuitShares(
        uint256 amount,
        address wantAddress
    ) external view returns (uint256 result) {
        if (amount == 0) return 0;
        uint256 usdcForMoeSwapAmount = amount / 2;
        uint256 usdcForWmntSwapAmount = amount - usdcForMoeSwapAmount;

        address[] memory toWmntPath = new address[](3);
        toWmntPath[0] = wantAddress;
        toWmntPath[1] = address(USDT);
        toWmntPath[2] = address(WMNT);
        uint256[] memory toWmntSwapResult = MoeMerchantLib
            .MOE_ROUTER
            .getAmountsOut(usdcForWmntSwapAmount, toWmntPath);
        uint256 wmntAmount = toWmntSwapResult[toWmntSwapResult.length - 1];

        address[] memory toMoePath = new address[](3);
        toMoePath[0] = wantAddress;
        toMoePath[1] = address(USDT);
        toMoePath[2] = address(MOE);
        uint256[] memory toMoeSwapResult = MoeMerchantLib
            .MOE_ROUTER
            .getAmountsOut(usdcForMoeSwapAmount, toMoePath);
        uint256 moeAmount = toMoeSwapResult[toMoeSwapResult.length - 1];

        IMoePair pair = IMoePair(
            MoeMerchantLib.MOE_FACTORY.getPair(address(MOE), address(WMNT))
        );
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
        address wantAddress
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

        address[] memory fromWmntPath = new address[](3);
        fromWmntPath[0] = address(WMNT);
        fromWmntPath[1] = address(USDT);
        fromWmntPath[2] = wantAddress;
        uint256[] memory fromWmntSwapResult = MoeMerchantLib
            .MOE_ROUTER
            .getAmountsOut(wmntAmount, fromWmntPath);
        result = fromWmntSwapResult[fromWmntSwapResult.length - 1];

        address[] memory fromMoepath = new address[](3);
        fromMoepath[0] = address(MOE);
        fromMoepath[1] = address(USDT);
        fromMoepath[2] = wantAddress;
        uint256[] memory fromMoeSwapResult = MoeMerchantLib
            .MOE_ROUTER
            .getAmountsOut(moeAmount, fromMoepath);
        result += fromMoeSwapResult[fromMoeSwapResult.length - 1];
    }

    function mintShares(
        uint256 amount,
        address wantAddress,
        uint256 moeTokensToAddToMoeLiquidity,
        uint256 wmntTokensToAddToMoeLiquidity,
        uint256 slippageBps,
        function() external view returns (uint256) balanceOfMoeLp,
        function() external view returns (uint256) balanceOfCircuitShares,
        function(address, uint256, address)
            external
            view
            returns (uint256) consult
    )
        external
        returns (
            uint256 resultingMoeTokensToAddToMoeLiquidity,
            uint256 resultingWmntTokensToAddToMoeLiquidity
        )
    {
        if (amount == 0)
            return (
                moeTokensToAddToMoeLiquidity,
                wmntTokensToAddToMoeLiquidity
            );
        uint256 oldLpBalance = balanceOfMoeLp();

        uint256 usdcForMoeSwapAmount = amount / 2;
        uint256 usdcForWmntSwapAmount = amount - usdcForMoeSwapAmount;

        address[] memory toWmntPath = new address[](3);
        toWmntPath[0] = wantAddress;
        toWmntPath[1] = address(USDT);
        toWmntPath[2] = address(WMNT);
        uint256 wmntAmount = MoeMerchantLib.moeMerchantSwapMulti(
            toWmntPath,
            usdcForWmntSwapAmount,
            slippageBps,
            consult
        );

        address[] memory toMoePath = new address[](3);
        toMoePath[0] = wantAddress;
        toMoePath[1] = address(USDT);
        toMoePath[2] = address(MOE);
        uint256 moeAmount = MoeMerchantLib.moeMerchantSwapMulti(
            toMoePath,
            usdcForMoeSwapAmount,
            slippageBps,
            consult
        );

        (uint256 lpMinted, uint256 moeLeft, uint256 wmntLeft) = MoeMerchantLib
            .moeMerchantAddLiquidity(
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
        function() external view returns (uint256) balanceOfMoeLp,
        function() external view returns (uint256) balanceOfCircuitShares,
        function(address, uint256, address)
            external
            view
            returns (uint256) consult
    ) external {
        if (shares == 0) return;
        uint256 oldLpBalance = balanceOfMoeLp();
        uint256 oldCircuitSharesBalance = balanceOfCircuitShares();
        CIRCUIT_VAULT.withdraw(shares);
        emit BurnedCircuitShares(
            oldCircuitSharesBalance,
            balanceOfCircuitShares()
        );
        (uint256 amountAWithdrawn, uint256 amountBWithdrawn) = MoeMerchantLib
            .moeMerchantRemoveLiquidity(
                address(MOE),
                address(WMNT),
                balanceOfMoeLp() - oldLpBalance
            );
        emit BurnedMoeLp(oldLpBalance, balanceOfMoeLp());

        address[] memory fromMoePath = new address[](3);
        fromMoePath[0] = address(MOE);
        fromMoePath[1] = address(USDT);
        fromMoePath[2] = wantAddress;
        uint256 swappedFromMoeUsdcAmount = MoeMerchantLib.moeMerchantSwapMulti(
            fromMoePath,
            amountAWithdrawn,
            slippageBps,
            consult
        );
        address[] memory fromWmntPath = new address[](3);
        fromWmntPath[0] = address(WMNT);
        fromWmntPath[1] = address(USDT);
        fromWmntPath[2] = wantAddress;
        uint256 swappedFromWmntUsdcAmount = MoeMerchantLib.moeMerchantSwapMulti(
            fromWmntPath,
            amountBWithdrawn,
            slippageBps,
            consult
        );
        emit WantTokensGathered(
            swappedFromWmntUsdcAmount + swappedFromMoeUsdcAmount
        );
    }
}
