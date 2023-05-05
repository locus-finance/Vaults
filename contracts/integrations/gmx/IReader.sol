// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IVault.sol";

interface IReader {
    function getMaxAmountIn(
        IVault _vault,
        address _tokenIn,
        address _tokenOut
    ) external returns (uint256);

    function getAmountOut(
        IVault _vault,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external returns (uint256, uint256);

    function getFeeBasisPoints(
        IVault _vault,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external returns (uint256, uint256, uint256);

    function getFees(
        address _vault,
        address[] memory _tokens
    ) external returns (uint256[] memory);

    function getTotalStaked(
        address[] memory _yieldTokens
    ) external returns (uint256[] memory);

    function getStakingInfo(
        address _account,
        address[] memory _yieldTrackers
    ) external returns (uint256[] memory);

    function getVestingInfo(
        address _account,
        address[] memory _vesters
    ) external returns (uint256[] memory);

    function getPairInfo(
        address _factory,
        address[] memory _tokens
    ) external returns (uint256[] memory);

    function getFundingRates(
        address _vault,
        address _weth,
        address[] memory _tokens
    ) external returns (uint256[] memory);

    function getTokenSupply(
        IERC20 _token,
        address[] memory _excludedAccounts
    ) external returns (uint256);

    function getTotalBalance(
        IERC20 _token,
        address[] memory _accounts
    ) external returns (uint256);

    function getTokenBalances(
        address _account,
        address[] memory _tokens
    ) external returns (uint256[] memory);

    function getTokenBalancesWithSupplies(
        address _account,
        address[] memory _tokens
    ) external returns (uint256[] memory);

    // function getPrices(IVaultPriceFeed _priceFeed, address[] memory _tokens) external returns (uint256[] memory);
    function getVaultTokenInfo(
        address _vault,
        address _weth,
        uint256 _usdgAmount,
        address[] memory _tokens
    ) external returns (uint256[] memory);

    function getFullVaultTokenInfo(
        address _vault,
        address _weth,
        uint256 _usdgAmount,
        address[] memory _tokens
    ) external returns (uint256[] memory);

    function getVaultTokenInfoV2(
        address _vault,
        address _weth,
        uint256 _usdgAmount,
        address[] memory _tokens
    ) external returns (uint256[] memory);

    function getPositions(
        address _vault,
        address _account,
        address[] memory _collateralTokens,
        address[] memory _indexTokens,
        bool[] memory _isLong
    ) external returns (uint256[] memory);
}
