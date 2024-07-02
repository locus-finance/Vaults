// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ILocusVaultToken} from "./ILocusVaultToken.sol";
import {StrategyParams} from "../../abstracts/BaseStrategyForSeparatedVault.sol";

interface ILocusVault {
    error OnlyAuthorized(address); //0x1748142d
    error V2(); //0xd30204e1
    error V3(); //0xb22f5305
    error V4(); //0x5f0c12c8
    error NotEnoughShares(); //0x309d83b1
    error ZeroToWithdraw(); //0xd498103e
    error UnacceptableLoss(); //0x03fe7f1c
    error InactiveStrategy(); //0x7ce4e353
    error V6(); //0x6818be95
    error V7(); //0x33378859
    error V8(); //0x33d7203e
    error V9(); //0x56c54560
    error V13(); //0x908776f1
    error V14(); //0xcc588483
    error V15(); //0x429bf29b
    error V17(); //0x0fc96878
    error DepositLimit(); //
    error UnacceptableFee();
    error MinMaxDebtError();
    error AmountIsIncorrect(uint256 amount);
    error CannotBurnMoreThanActualBalance();
    error OnlyAuthorizedOrStrategy();
    error DurationCannotBeZero();
    error AlreadyAdded(address strategy);
    error AlreadyRemoved(address strategy);

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

    event NewPerformanceFeeCalculated(uint256 indexed newPerformanceFee);

    function initialize(
        IERC20Metadata _token,
        address _admin,
        address treasury
    ) external;

    function token() external view returns (IERC20Metadata);

    function vaultToken() external view returns (ILocusVaultToken);

    function revokeFunds() external;

    function totalAssets() external view returns (uint256);

    function getStrategyParams(address strategyAddress) external view returns (StrategyParams memory);

    function deposit(
        uint256 _amount,
        address _recipient
    ) external returns (uint256);

    function withdraw(
        uint256 _maxShares,
        address _recipient,
        uint256 _maxLoss
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

    function debtOutstanding() external view returns (uint256);

    function report(
        uint256 _gain,
        uint256 _loss,
        uint256 _debtPayment
    ) external returns (uint256);

    function updateLastPricePerShare() external;
}
