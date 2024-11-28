// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IVaultToken} from "./IVaultToken.sol";

/**
 * @dev Struct representing the off-chain data of a strategy.
 * @param YtToWantRate The rate of conversion from YT token to WANT token.
 * @param WantToLpYtProportion The proportion of WANT token to LP YT token.
 * @param PtToSyRate The rate of conversion from PT token to SY token.
 * @param SyToPtRate The rate of conversion from SY token to PT token.
 * @param LpToSyPtProportion The proportion of LP token to SY and PT tokens.
 * @param PyToAssetRate The rate of conversion from PY token to asset token.
 * @param SyToAssetRate The rate of conversion from SY token to asset token.
 * @param swapData The swap data for Pendle router.
 */
struct OffChainData {
    uint256 YtToWantRate;
    uint256[2] WantToLpYtProportion;
    uint256 PtToSyRate;
    uint256 SyToPtRate;
    uint256[2] LpToSyPtProportion;
    uint256 PyToAssetRate;
    uint256 SyToAssetRate;
    uint256 nonce;
}

struct StrategyParams {
    uint256 performanceFee;
    uint256 activation;
    uint256 debtRatio;
    uint256 minDebtPerHarvest;
    uint256 maxDebtPerHarvest;
    uint256 lastReport;
    uint256 totalDebt;
    uint256 totalGain;
    uint256 totalLoss;
}

interface ILocusVaultPendle {
    error Vault__OnlyAuthorized(address); //0x1748142d
    error Vault__V2(); //0xd30204e1
    error Vault__V3(); //0xb22f5305
    error Vault__V4(); //0x5f0c12c8
    error Vault__NotEnoughShares(); //0x309d83b1
    error Vault__ZeroToWithdraw(); //0xd498103e
    error Vault__UnacceptableLoss(); //0x03fe7f1c
    error Vault__InactiveStrategy(); //0x7ce4e353
    error Vault__V6(); //0x6818be95
    error Vault__V7(); //0x33378859
    error Vault__V8(); //0x33d7203e
    error Vault__V9(); //0x56c54560
    error Vault__V13(); //0x908776f1
    error Vault__V14(); //0xcc588483
    error Vault__V15(); //0x429bf29b
    error Vault__V17(); //0x0fc96878
    error Vault__DepositLimit(); //
    error Vault__UnAcceptableFee();
    error Vault__MinMaxDebtError();
    error Vault__AmountIsIncorrect(uint256 amount);

    event StrategyWithdrawnSome(
        address indexed strategy,
        uint256 amount,
        uint256 loss
    );
    event StrategyReported(
        address strategy,
        uint256 gain,
        uint256 loss,
        uint256 debtPaid,
        uint256 totalGain,
        uint256 totalLoss,
        uint256 totalDebt,
        uint256 debtAdded,
        uint256 debtRatio
    );

    event Withdraw(
        address indexed recipient,
        uint256 indexed shares,
        uint256 indexed value,
        uint256 timestamp
    );

    event Deposit(
        address indexed recipient,
        uint256 indexed shares,
        uint256 indexed value,
        uint256 timestamp
    );

    function initialize(
        IERC20 _token,
        address _admin,
        address treasury,
        address _dataSigner
    ) external;

    function token() external view returns (IERC20);

    function vaultToken() external view returns(IVaultToken);

    function revokeFunds() external;

    function totalAssets() external view returns (uint256);

    function deposit(
        uint256 _amount,
        address _recipient
    ) external returns (uint256);

    function withdraw(
        uint256 _maxShares,
        address _recipient,
        uint256 _maxLoss,
        OffChainData[] calldata _offChainData,
        bytes[] memory signatures
    ) external;

    function addStrategy(
        address _strategy,
        uint256 _debtRatio,
        uint256 _performanceFee,
        uint256 _minDebtPerHarvest,
        uint256 _maxDebtPerHarvest
    ) external;

    function pricePerShare() external view returns (uint256);

    function revokeStrategy(address _strategy) external;

    function updateStrategyDebtRatio(
        address _strategy,
        uint256 _debtRatio
    ) external;

    function debtOutstanding() external view returns(uint256);

    function report(
        uint256 _gain,
        uint256 _loss,
        uint256 _debtPayment
    ) external returns (uint256);

}