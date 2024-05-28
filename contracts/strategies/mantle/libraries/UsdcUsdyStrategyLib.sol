// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./MoeMerchantLib.sol";
import "../../../integrations/circuit/ICircuitVault.sol";
import "../../../integrations/merchantMoe/IMoePair.sol";

library UsdcUsdyStrategyLib {
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
        ICircuitVault(0xc425A0fC1e62bEDa428Ff628597dC8EA1C13d0e4);
    IERC20 public constant USDY =
        IERC20(0x5bE26527e817998A7206475496fDE1E68957c5A6);
    IERC20 public constant MOE_MERCHANT_USDC_USDY_POOL =
        IERC20(0xc1f43E45F86E7bfb92C3c309b0eF366F9Ba33Bfa);

    function wantToCircuitShares(
        uint256 amount,
        address wantAddress
    ) external view returns (uint256 result) {
        if (amount == 0) return 0;
        address[] memory path = new address[](2);
        path[0] = wantAddress;
        path[1] = address(USDY);
        uint256 amountAToAdd = amount / 2;
        uint256 amountAToSwapToB = amount - amountAToAdd;
        IMoePair pair = IMoePair(
            MoeMerchantLib.MOE_FACTORY.getPair(wantAddress, address(USDY))
        );
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 amountBToAdd = MoeMerchantLib.MOE_ROUTER.getAmountsOut(amountAToSwapToB, path)[
            1
        ];
        uint256 lpTotalSupply = pair.totalSupply();
        uint256 liquidity = Math.min(
            (amountAToAdd * lpTotalSupply) / reserve0,
            (amountBToAdd * lpTotalSupply) / reserve1
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
            MoeMerchantLib.MOE_FACTORY.getPair(wantAddress, address(USDY))
        );
        uint256 lpTotalSupply = pair.totalSupply();
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        result = (liquidity * reserve0) / lpTotalSupply;
        uint256 usdyAmount = (liquidity * reserve1) / lpTotalSupply;
        address[] memory path = new address[](2);
        path[0] = address(USDY);
        path[1] = wantAddress;
        result += MoeMerchantLib.MOE_ROUTER.getAmountsOut(usdyAmount, path)[1];
    }

    function mintShares(
        uint256 amount,
        address wantAddress,
        uint256 wantTokensToAddToMoeLiquidity,
        uint256 usdyTokensToAddToMoeLiquidity,
        uint256 slippageBps,
        function() external view returns (uint256) balanceOfMoeLp,
        function() external view returns (uint256) balanceOfCircuitShares,
        function(address, uint256, address) external view returns(uint256) consult
    ) 
        external
        returns (
            uint256 resultingWantTokensToAddToMoeLiquidity,
            uint256 resultingUsdyTokensToAddToMoeLiquidity
        )
    {
        if (amount == 0) return (wantTokensToAddToMoeLiquidity, usdyTokensToAddToMoeLiquidity);
        uint256 oldLpBalance = balanceOfMoeLp();
        (uint256 lpMinted, uint256 wantLeft, uint256 usdyLeft) = MoeMerchantLib.moeMerchantAddLiquiditySingle(
            wantAddress,
            address(USDY),
            amount,
            slippageBps,
            consult
        );
        if (wantLeft > 0) {
            resultingWantTokensToAddToMoeLiquidity = wantLeft;
        }
        if (usdyLeft > 0) {
            resultingUsdyTokensToAddToMoeLiquidity = usdyLeft;
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
                wantAddress,
                address(USDY),
                balanceOfMoeLp() - oldLpBalance
            );
        emit BurnedMoeLp(oldLpBalance, balanceOfMoeLp());

        uint256 usdyToUsdcSwappedAmount = MoeMerchantLib.moeMerchantSwap(
            address(USDY),
            wantAddress,
            amountBWithdrawn,
            slippageBps,
            consult
        );
        emit WantTokensGathered(
            amountAWithdrawn + usdyToUsdcSwappedAmount
        );
    }
}