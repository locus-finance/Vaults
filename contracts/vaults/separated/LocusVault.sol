// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {StrategyParams, BaseStrategyForSeparatedVault} from "../../abstracts/BaseStrategyForSeparatedVault.sol";
import {ILocusVaultToken} from "../../interfaces/separatedVault/ILocusVaultToken.sol";
import {ILocusVault} from "../../interfaces/separatedVault/ILocusVault.sol";

contract LocusVault is
    Initializable,
    ILocusVault,
    UUPSUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for ILocusVaultToken;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    uint256 public constant SECS_PER_YEAR = 31_556_952;
    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant DEGRADATION_COEFFICIENT = 10 ** 18;
    uint256 public constant LOCKED_PROFIT_DEGRADATION = (DEGRADATION_COEFFICIENT * 46) / 10 ** 6;

    IERC20Metadata public override token;
    ILocusVaultToken public vaultToken;
    
    uint256 public lockedProfit;
    uint256 public lastReport;
    address public treasury;
    uint256 public depositLimit;
    uint256 public totalDebtRatio;
    uint256 public totalDebt;
    uint256 public managementFee;
    /// @dev Following `performanceFee` is used only for an initial value of performance fee.
    uint256 public performanceFee;
    bool public emergencyShutdown;

    mapping(address => StrategyParams) public strategies;

    address[] public strategiesList;
    mapping(address strategy => uint256 position) public strategyPositionInArray;
    uint256 public lastPricePerShare;

    function totalSupply() public view returns (uint256) {
        return vaultToken.totalSupply();
    }

    modifier checkAmountOnDeposit(uint256 amount) {
        if (amount + totalAssets() > depositLimit || amount == 0) {
            revert AmountIsIncorrect(amount);
        }
        _;
    }

    function initialize(
        IERC20Metadata _token,
        address _admin,
        address _treasury
    ) external initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        address sender = _msgSender();
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, sender);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(DEFAULT_ADMIN_ROLE, sender);
        token = _token;
        treasury = _treasury;
    }

    function decimals() public view virtual returns (uint8) {
        return vaultToken.decimals();
    }

    function revokeFunds() external onlyRole(ADMIN_ROLE) {
        payable(_msgSender()).transfer(address(this).balance);
    }

    function setEmergencyShutdown(
        bool _emergencyShutdown
    ) external onlyRole(ADMIN_ROLE) {
        emergencyShutdown = _emergencyShutdown;
    }

    function setTreasury(address _newTreasuryAddress) external onlyRole(ADMIN_ROLE) {
        treasury = _newTreasuryAddress;
    }

    function setDepositLimit(uint256 _limit) external onlyRole(ADMIN_ROLE) {
        depositLimit = _limit;
    }

    function setVaultToken(ILocusVaultToken _newToken) external onlyRole(ADMIN_ROLE) {
        vaultToken = _newToken;
    }

    //!Tests are not working with this implementation of PPS
    function totalAssets() public view returns (uint256 _assets) {
        for (uint256 i = 0; i < strategiesList.length; i++) {
            _assets += BaseStrategyForSeparatedVault(strategiesList[i])
                .estimatedTotalAssets();
        }
        _assets += totalIdle();
        // _assets += totalIdle() + totalDebt;
    }

    function setInitialPerformanceFee(uint256 fee) external onlyRole(ADMIN_ROLE) {
        if (fee > MAX_BPS / 2) revert UnacceptableFee();
        performanceFee = fee;
    }

    function setManagementFee(uint256 fee) external onlyRole(ADMIN_ROLE) {
        if (fee > MAX_BPS) revert UnacceptableFee();
        managementFee = fee;
    }

    function totalIdle() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function updateStrategyMinDebtPerHarvest(
        address strategy,
        uint256 _minDebtPerHarvest
    ) external onlyRole(ADMIN_ROLE) {
        if (strategies[strategy].activation == 0)
            revert InactiveStrategy();
        if (strategies[strategy].maxDebtPerHarvest <= _minDebtPerHarvest)
            revert MinMaxDebtError();
        strategies[strategy].minDebtPerHarvest = _minDebtPerHarvest;
    }

    function updateStrategyMaxDebtPerHarvest(
        address strategy,
        uint256 _maxDebtPerHarvest
    ) external onlyRole(ADMIN_ROLE) {
        if (strategies[strategy].activation == 0)
            revert InactiveStrategy();
        if (strategies[strategy].minDebtPerHarvest >= _maxDebtPerHarvest)
            revert MinMaxDebtError();
        strategies[strategy].maxDebtPerHarvest = _maxDebtPerHarvest;
    }

    function deposit(
        uint256 _amount,
        address _recipient
    ) external checkAmountOnDeposit(_amount) returns (uint256) {
        return _deposit(_amount, _recipient);
    }

    function deposit(
        uint256 _amount
    ) external checkAmountOnDeposit(_amount) returns (uint256) {
        return _deposit(_amount, _msgSender());
    }

    function withdraw(
        uint256 _maxShares,
        address _recipient,
        uint256 _maxLoss
    ) external {
        _initiateWithdraw(_maxShares, _recipient, _maxLoss);
    }

    function getStrategyParams(address strategyAddress) external view returns (StrategyParams memory) {
        return strategies[strategyAddress];
    }

    function addStrategy(
        address _strategy,
        uint256 _debtRatio,
        uint256 _performanceFee,
        uint256 _minDebtPerHarvest,
        uint256 _maxDebtPerHarvest
    ) external onlyRole(ADMIN_ROLE) {
        if (strategies[_strategy].activation != 0) revert V2();
        if (totalDebtRatio + _debtRatio > MAX_BPS) revert V3();
        if (_performanceFee > MAX_BPS / 2) revert UnacceptableFee();
        if (_minDebtPerHarvest > _maxDebtPerHarvest)
            revert MinMaxDebtError();
        strategies[_strategy] = StrategyParams({
            performanceFee: _performanceFee,
            activation: block.timestamp,
            debtRatio: _debtRatio,
            minDebtPerHarvest: _minDebtPerHarvest,
            maxDebtPerHarvest: _maxDebtPerHarvest,
            lastReport: 0,
            totalDebt: 0,
            totalGain: 0,
            totalLoss: 0
        });

        totalDebtRatio += _debtRatio;
        strategyPositionInArray[_strategy] = strategiesList.length;
        strategiesList.push(_strategy);
    }

    function debtOutstanding(
        address _strategy
    ) external view returns (uint256) {
        return _debtOutstanding(_strategy);
    }

    function debtOutstanding() external view returns (uint256) {
        return _debtOutstanding(_msgSender());
    }

    function creditAvailable(
        address _strategy
    ) external view returns (uint256) {
        return _creditAvailable(_strategy);
    }

    function _initiateWithdraw(
        uint256 maxShares,
        address recipient,
        uint256 maxLoss 
    ) internal returns (uint256) {
        uint256 shares = maxShares;
        if (maxLoss > MAX_BPS) revert V4();
        if (shares == type(uint256).max) {
            shares = vaultToken.balanceOf(_msgSender());
        }
        if (shares > vaultToken.balanceOf(_msgSender())) revert NotEnoughShares();
        if (shares == 0) revert ZeroToWithdraw();

        uint256 value = _shareValue(shares);
        uint256 vaultBalance = totalIdle();
        if (value > vaultBalance) {
            uint256 totalLoss;
            for (uint256 i = 0; i < strategiesList.length; i++) {
                if (value <= vaultBalance) {
                    break;
                }
                uint256 amountNeeded = value - vaultBalance;
                amountNeeded = Math.min(
                    amountNeeded,
                    // IBaseStrategy(strategiesList[i]).estimatedTotalAssets()
                    strategies[strategiesList[i]].totalDebt
                );
                if (amountNeeded == 0) {
                    continue;
                }
                uint256 balanceBefore = token.balanceOf(address(this));
                uint256 loss = BaseStrategyForSeparatedVault(strategiesList[i]).withdraw(
                    amountNeeded
                );
                uint256 withdrawn = token.balanceOf(address(this)) -
                    balanceBefore;
                vaultBalance += withdrawn;
                if (loss > 0) {
                    value -= loss;
                    totalLoss += loss;
                    _reportLoss(strategiesList[i], loss);
                }
                strategies[strategiesList[i]].totalDebt -= withdrawn;
                totalDebt -= withdrawn;
                emit StrategyWithdrawnSome(
                    strategiesList[i],
                    strategies[strategiesList[i]].totalDebt,
                    loss
                );
            }
            if (value > vaultBalance) {
                value = vaultBalance;
                shares = _sharesForAmount(value + totalLoss);
                if (shares >= vaultToken.balanceOf(_msgSender())) {
                    revert CannotBurnMoreThanActualBalance();
                }
            }
            if (totalLoss > (maxLoss * (value + totalLoss)) / MAX_BPS) {
                revert UnacceptableLoss();
            }
        }

        vaultToken.burn(_msgSender(), shares);
        token.safeTransfer(recipient, value);
        emit Withdraw(recipient, shares, value, block.timestamp);
        return value;
    }

    function pricePerShare() public view returns (uint256) {
        return _shareValue(10 ** decimals());
    }

    function revokeStrategy(address _strategy) external onlyRole(ADMIN_ROLE) {
        _revokeStrategy(_strategy);
    }

    function revokeStrategy() external {
        address sender = _msgSender();
        if (!hasRole(ADMIN_ROLE, sender) && sender != strategiesList[strategyPositionInArray[sender]]) {
            revert OnlyAuthorizedOrStrategy();
        }
        _revokeStrategy(sender);
    }

    function updateStrategyDebtRatio(
        address _strategy,
        uint256 _debtRatio
    ) external onlyRole(ADMIN_ROLE) {
        if (strategies[_strategy].activation == 0)
            revert InactiveStrategy();

        totalDebtRatio -= strategies[_strategy].debtRatio;
        strategies[_strategy].debtRatio = _debtRatio;
        if (totalDebtRatio + _debtRatio > MAX_BPS) revert V6();
        totalDebtRatio += _debtRatio;
    }

    function migrateStrategy(
        address _oldStrategy,
        address _newStrategy
    ) external onlyRole(ADMIN_ROLE) {
        if (_newStrategy == address(0)) revert V7();
        if (strategies[_oldStrategy].activation == 0) revert V8();
        if (strategies[_newStrategy].activation > 0) revert V9();
        StrategyParams memory params = strategies[_oldStrategy];
        _revokeStrategy(_oldStrategy);
        totalDebtRatio += params.debtRatio;

        strategies[_newStrategy] = StrategyParams({
            performanceFee: params.performanceFee,
            activation: params.lastReport,
            debtRatio: params.debtRatio,
            minDebtPerHarvest: params.minDebtPerHarvest,
            maxDebtPerHarvest: params.maxDebtPerHarvest,
            lastReport: params.lastReport,
            totalDebt: params.totalDebt,
            totalGain: 0,
            totalLoss: 0
        });
        strategies[_oldStrategy].totalDebt = 0;

        BaseStrategyForSeparatedVault(_oldStrategy).migrate(_newStrategy);
        strategiesList[strategyPositionInArray[_oldStrategy]] = _newStrategy;
        strategyPositionInArray[_newStrategy] = strategyPositionInArray[
            _oldStrategy
        ];
        strategyPositionInArray[_oldStrategy] = 0;
    }

    function _deposit(
        uint256 _amount,
        address _recipient
    ) internal returns (uint256) {
        if (emergencyShutdown) revert V13();
        uint256 shares = _issueSharesForAmount(_recipient, _amount);
        token.safeTransferFrom(_msgSender(), address(this), _amount);
        emit Deposit(_recipient, shares, _amount, block.timestamp);
        return shares;
    }

    function report(
        uint256 _gain,
        uint256 _loss,
        uint256 _debtPayment
    ) external returns (uint256) {
        if (strategies[_msgSender()].activation == 0) revert V14();

        if (_loss > 0) {
            _reportLoss(_msgSender(), _loss);
        }
        uint256 totalFees = _assessFees(_msgSender(), _gain);
        strategies[_msgSender()].totalGain += _gain;
        uint256 credit = _creditAvailable(_msgSender());

        uint256 debt = _debtOutstanding(_msgSender());
        uint256 debtPayment = Math.min(debt, _debtPayment);

        if (debtPayment > 0) {
            strategies[_msgSender()].totalDebt -= debtPayment;
            totalDebt -= debtPayment;
            debt -= debtPayment;
        }

        if (credit > 0) {
            strategies[_msgSender()].totalDebt += credit;
            totalDebt += credit;
        }

        uint256 totalAvail = _gain + debtPayment;

        if (totalAvail < credit) {
            token.safeTransfer(_msgSender(), credit - totalAvail);
        } else if (totalAvail > credit) {
            token.safeTransferFrom(
                _msgSender(),
                address(this),
                totalAvail - credit
            );
        }

        uint256 lockedProfitBeforeLoss = _calculateLockedProfit() +
            _gain -
            totalFees;
        if (lockedProfitBeforeLoss > _loss) {
            lockedProfit = lockedProfitBeforeLoss - _loss;
        } else {
            lockedProfit = 0;
        }

        strategies[_msgSender()].lastReport = block.timestamp;
        lastReport = block.timestamp;

        StrategyParams memory params = strategies[_msgSender()];
        emit StrategyReported(
            _msgSender(),
            _gain,
            _loss,
            _debtPayment,
            params.totalGain,
            params.totalLoss,
            params.totalDebt,
            credit,
            params.debtRatio
        );
        if (strategies[_msgSender()].debtRatio == 0 || emergencyShutdown) {
            return BaseStrategyForSeparatedVault(_msgSender()).estimatedTotalAssets();
        } else {
            return debt;
        }
    }

    function _calculateLockedProfit() internal view returns (uint256) {
        uint256 lockedFundsRatio = (block.timestamp - lastReport) *
            LOCKED_PROFIT_DEGRADATION;
        if (lockedFundsRatio < DEGRADATION_COEFFICIENT) {
            uint256 _lockedProfit = lockedProfit;
            return
                _lockedProfit -
                ((lockedFundsRatio * _lockedProfit) / DEGRADATION_COEFFICIENT);
        } else {
            return 0;
        }
    }

    function _reportLoss(address _strategy, uint256 _loss) internal {
        if (strategies[_strategy].totalDebt < _loss) revert V15();

        if (totalDebtRatio != 0) {
            uint256 ratioChange = Math.min(
                (_loss * totalDebtRatio) / totalDebt,
                strategies[_strategy].debtRatio
            );
            strategies[_strategy].debtRatio -= ratioChange;
            totalDebtRatio -= ratioChange;
        }
        strategies[_strategy].totalLoss += _loss;
        strategies[_strategy].totalDebt -= _loss;
        totalDebt -= _loss;
    }

    function _freeFunds() internal view returns (uint256) {
        return totalAssets() - _calculateLockedProfit();
    }

    function _shareValue(uint256 _shares) internal view returns (uint256) {
        if (totalSupply() == 0) {
            return _shares;
        }
        return (_shares * _freeFunds()) / totalSupply();
    }

    function _sharesForAmount(uint256 amount) internal view returns (uint256) {
        uint256 _freeFund = _freeFunds();
        if (_freeFund > 0) {
            return ((amount * totalSupply()) / _freeFund);
        } else {
            return 0;
        }
    }

    function maxAvailableShares() external view returns (uint256) {
        uint256 shares = _sharesForAmount(totalIdle());
        for (uint256 i = 0; i < strategiesList.length; i++) {
            shares += _sharesForAmount(
                strategies[strategiesList[i]].totalDebt
            );
        }
        return shares;
    }

    function _issueSharesForAmount(
        address _to,
        uint256 _amount
    ) internal returns (uint256) {
        uint256 shares = 0;
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            shares = _amount;
        } else {
            shares = (_amount * _totalSupply) / _freeFunds();
        }
        if (shares == 0) revert V17();
        vaultToken.mint(_to, shares);
        return shares;
    }

    function _revokeStrategy(address _strategy) internal {
        totalDebtRatio -= strategies[_strategy].debtRatio;
        strategies[_strategy].debtRatio = 0;
    }

    function _creditAvailable(
        address _strategy
    ) internal view returns (uint256) {
        if (emergencyShutdown) {
            return 0;
        }
        uint256 strategyDebtLimit = (strategies[_strategy].debtRatio *
            totalAssets()) / MAX_BPS;
        uint256 strategyTotalDebt = strategies[_strategy].totalDebt;

        uint256 vaultDebtLimit = (totalDebtRatio * totalAssets()) / MAX_BPS;
        uint256 vaultTotalDebt = totalDebt;

        if (
            strategyDebtLimit <= strategyTotalDebt ||
            vaultDebtLimit <= totalDebt
        ) {
            return 0;
        }
        uint256 available = strategyDebtLimit - strategyTotalDebt;
        available = Math.min(available, vaultDebtLimit - vaultTotalDebt);
        return Math.min(totalIdle(), available);
    }

    function _debtOutstanding(
        address _strategy
    ) internal view returns (uint256) {
        if (totalDebtRatio == 0) {
            return strategies[_strategy].totalDebt;
        }
        uint256 strategyDebtLimit = (strategies[_strategy].debtRatio *
            totalAssets()) / MAX_BPS;
        uint256 strategyTotalDebt = strategies[_strategy].totalDebt;

        if (emergencyShutdown) {
            return strategyTotalDebt;
        } else if (strategyTotalDebt <= strategyDebtLimit) {
            return 0;
        } else {
            return strategyTotalDebt - strategyDebtLimit;
        }
    }

    function previewPerformanceFee() public view returns (uint256) {
        uint256 _lastPricePerShare = lastPricePerShare; 
        uint256 currentPps = pricePerShare();
        if (_lastPricePerShare >= currentPps) return 0;
        uint256 localPrecision = 10 ** token.decimals();
        uint256 diff = currentPps - _lastPricePerShare;
        uint256 nominator = diff * performanceFee;
        uint256 denominator = MAX_BPS * localPrecision; 
        if (nominator < denominator) return 1;
        return nominator * MAX_BPS / denominator;
    }

    function _calculatePerformanceFee() internal returns (uint256) {
        if (lastPricePerShare == 0) {
            lastPricePerShare = pricePerShare();
            return performanceFee;
        }
        return previewPerformanceFee();   
    }

    function _assessFees(
        address strategy,
        uint256 gain
    ) internal returns (uint256) {
        if (strategies[strategy].activation == block.timestamp) {
            return 0;
        }

        uint256 duration = block.timestamp - strategies[strategy].lastReport;
        if (duration == 0) {
            revert DurationCannotBeZero();
        }
        if (gain == 0) {
            return 0;
        }
        uint256 _managementFee = (strategies[strategy].totalDebt -
            duration *
            managementFee) /
            MAX_BPS /
            SECS_PER_YEAR;
        uint256 _performanceFee = (gain * _calculatePerformanceFee()) / MAX_BPS;
        uint256 totalFee = _managementFee + _performanceFee;
        if (totalFee > gain) {
            totalFee = gain;
        }
        if (totalFee > 0) {
            if (vaultToken.balanceOf(address(this)) > 0) {
                vaultToken.safeTransfer(treasury, vaultToken.balanceOf(address(this)));
            }
        }
        return totalFee;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    receive() external payable {}
}