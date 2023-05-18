// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../interfaces/IWETH.sol";
import "../integrations/uniswap/v3/IV3SwapRouter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @author @pillardev
 * @title  uniswap v3 integration
 */
abstract contract DexSwapper {
    IV3SwapRouter public amm;
    IUniswapV3Factory public factory;
    address public WETH;
    uint24[] public fees;

    event Swapped(
        address indexed tokenA,
        address indexed tokenB,
        address recipient,
        uint256 amount
    );
    event DexUpgraded(address factoryAddress, address ammAddress);

    /**
     * @notice set dex addresses
     * @param newFactory dexFactory address and dexRouter address
     */
    function _setDex(address newFactory, address newAmm) internal {
        amm = IV3SwapRouter(newAmm);
        factory = IUniswapV3Factory(newFactory);
        IERC20(WETH).approve(newAmm, type(uint256).max);
        emit DexUpgraded(newFactory, newAmm);
    }

    /**
     * @notice set fee levels for pool
     * @param newFees fee array
     */
    function _setFeesLevels(uint24[] memory newFees) internal {
        require(
            newFees.length > 0,
            "DexSwapper::setFeesLevels: invalid uniswap fee levels"
        );
        fees = newFees;
    }

    function _approve(
        address _baseAsset,
        address _spender,
        uint256 _amount
    ) internal {
        IERC20(_baseAsset).approve(_spender, _amount);
    }

    /**
     * @notice Swap exact input
     * @param tokenA tokenA, tokenB, amount, recipient params for swap
     */
    function _swap(
        address tokenA,
        address tokenB,
        uint256 amount,
        address recipient
    ) internal returns (uint256) {
        address swapTokenA = tokenA;
        address swapTokenB = tokenB;
        address swapRecipient = recipient;
        if (tokenA != address(0x0)) {
            require(
                IERC20(tokenA).balanceOf(address(this)) >= amount,
                "DexSwapper::swap: deposit or bridge swap amountIn"
            );
            IERC20(tokenA).approve(address(amm), amount);
        } else {
            require(msg.value == amount, "DexSwapper::swap: amount mismatch");
            swapTokenA = WETH;
            IWETH(WETH).deposit{value: msg.value}();
        }
        if (tokenB == address(0x0)) {
            swapTokenB = WETH;
            swapRecipient = address(this);
        }

        (, uint24 fee, , ) = getBestFee(swapTokenA, swapTokenB);
        require(fee != 0, "DexSwapper::swap: no pool");

        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter
            .ExactInputSingleParams({
                tokenIn: swapTokenA,
                tokenOut: swapTokenB,
                fee: fee,
                recipient: swapRecipient,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        uint256 output = amm.exactInputSingle(params);

        if (tokenB == address(0x0)) {
            IWETH(WETH).withdraw(output);
            if (!payable(recipient).send(output)) {
                IERC20(WETH).transfer(recipient, output);
            }
        }

        emit Swapped(swapTokenA, swapTokenB, swapRecipient, amount);
        return output;
    }

    /**
     * @notice returns swap status for tokens
     * @param bridgeToken sgBridge token address
     * @param tokens array of tokens
     * @return bool
     */
    function isTokensSupported(
        address bridgeToken,
        address[] memory tokens
    ) public view returns (bool[] memory) {
        bool[] memory results = new bool[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            results[i] = isTokenSupported(bridgeToken, tokens[i]);
        }
        return results;
    }

    /**
     * @notice returns swap status for tokens
     * @param tokens array of token's pairs
     * @return bool
     */
    function isPairsSupported(
        address[][] calldata tokens
    ) public view returns (bool[] memory) {
        bool[] memory results = new bool[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            (address pool, , , ) = getBestFee(tokens[i][0], tokens[i][1]);
            results[i] = pool != address(0);
        }
        return results;
    }

    /**
     * @notice returns best fee for pair
     * @param tokenA first token in pair
     * @param tokenB second token in pair
     * @return pool, fee, tokenA, tokenB
     */
    function getBestFee(
        address tokenA,
        address tokenB
    ) public view returns (address, uint24, address, address) {
        if (tokenA == tokenB) {
            return (tokenA, 0, tokenA, tokenB);
        }
        address swapTokenA = tokenA;
        address swapTokenB = tokenB;
        if (tokenA == address(0x0)) {
            swapTokenA = WETH;
        }
        if (tokenB == address(0x0)) {
            swapTokenB = WETH;
        }
        for (uint256 i = 0; i < fees.length; i++) {
            address pool = factory.getPool(swapTokenA, swapTokenB, fees[i]);
            if (pool != address(0)) {
                return (pool, fees[i], swapTokenA, swapTokenB);
            }
        }
        return (address(0x0), 0, swapTokenA, swapTokenB);
    }

    function isTokenSupported(
        address bridgeToken,
        address token
    ) public view returns (bool) {
        if (bridgeToken == token) {
            return true;
        } else {
            (address pool, , , ) = getBestFee(bridgeToken, token);
            return pool != address(0);
        }
    }
}
