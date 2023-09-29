// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { StrategyParams, IOnChainVault } from "./interfaces/IOnChainVault.sol";
import { IBaseStrategy } from "./interfaces/IBaseStrategy.sol";

import "hardhat/console.sol";

contract OnChainVault is
    Initializable,
    ERC20Upgradeable,
    IOnChainVault,
    OwnableUpgradeable
{
    using SafeERC20 for IERC20;
    using SafeERC20 for ERC20;

    function initialize(
        IERC20 _token,
        address _governance,
        address treasury,
        string calldata name,
        string calldata symbol
    ) external initializer {
        __Ownable_init();
        __ERC20_init(name, symbol);

        governance = _governance;
        token = _token;
        approve(treasury, type(uint256).max);
    }

    uint256 public constant MAX_BPS = 10_000;

    address public override governance;
    IERC20 public override token;
    uint256 public depositLimit;
    uint256 public totalDebtRatio;
    uint256 public totalDebt;
    bool public emergencyShutdown;
    mapping(address => StrategyParams) public strategies;
    mapping(address strategy => uint256 position)
        public strategyPositionInArray;

    address[] public OnChainStrategies;

    modifier onlyAuthorized() {
        if (msg.sender != governance || msg.sender != owner())
            revert Vault__OnlyAuthorized(msg.sender);
        _;
    }

    function decimals() public view virtual override returns (uint8) {
        return ERC20(address(token)).decimals();
    }

    function revokeFunds() external onlyAuthorized {
        payable(msg.sender).transfer(address(this).balance);
    }

    function setEmergencyShutdown(
        bool _emergencyShutdown
    ) external onlyAuthorized {
        emergencyShutdown = _emergencyShutdown;
    }

    function setDepositLimit(uint256 _limit) external onlyAuthorized {
        depositLimit = _limit;
    }

    function totalAssets() public view returns (uint256 _assets) {
        for (uint256 i = 0; i < OnChainStrategies.length; i++) {
            _assets += IBaseStrategy(OnChainStrategies[i])
                .estimatedTotalAssets();
        }
        _assets += totalIdle();
    }

    function totalIdle() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function deposit(
        uint256 _amount,
        address _recipient
    ) external returns (uint256) {
        if (_amount > depositLimit) revert Vault__DepositLimit();
        return _deposit(_amount, _recipient);
    }

    function deposit(uint256 _amount) external returns (uint256) {
        if (_amount > depositLimit) revert Vault__DepositLimit();
        return _deposit(_amount, msg.sender);
    }

    function withdraw(
        uint256 _maxShares,
        address _recipient,
        uint256 _maxLoss
    ) external {
        _initiateWithdraw(_maxShares, _recipient, _maxLoss);
    }

    function addStrategy(
        address _strategy,
        uint256 _debtRatio,
        uint256 _performanceFee
    ) external onlyAuthorized {
        if (strategies[_strategy].activation != 0) revert Vault__V2();
        if (totalDebtRatio + _debtRatio > MAX_BPS) revert Vault__V3();

        strategies[_strategy] = StrategyParams({
            activation: block.timestamp,
            debtRatio: _debtRatio,
            totalDebt: 0,
            totalGain: 0,
            totalLoss: 0,
            lastReport: 0,
            performanceFee: _performanceFee
        });

        totalDebtRatio += _debtRatio;
        strategyPositionInArray[_strategy] = OnChainStrategies.length;
        OnChainStrategies.push(_strategy);
    }

    function debtOutstanding(
        address _strategy
    ) external view returns (uint256) {
        return _debtOutstanding(_strategy);
    }

    function debtOutstanding() external view returns (uint256) {
        //require needed to check if caller is strategy?
        return _debtOutstanding(msg.sender);
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
        if (maxLoss > MAX_BPS) revert Vault__V4();
        if (shares == type(uint256).max) {
            shares = balanceOf(msg.sender);
        }
        if (shares > balanceOf(msg.sender)) revert Vault__NotEnoughShares();
        if (shares == 0) revert Vault__ZeroToWithdraw();

        uint256 value = _shareValue(shares);
        // in our version vaultBalance is totalIdle?
        uint256 vaultBalance = totalIdle();
        if (value > vaultBalance) {
            uint256 totalLoss;
            for (uint256 i = 0; i < OnChainStrategies.length; i++) {
                if (value <= vaultBalance) {
                    break;
                }
                uint256 amountNeeded = value - vaultBalance;
                amountNeeded = Math.min(
                    amountNeeded,
                    strategies[OnChainStrategies[i]].totalDebt
                );
                if (amountNeeded == 0) {
                    continue;
                }
                uint256 balanceBefore = token.balanceOf(address(this));
                uint256 loss = IBaseStrategy(OnChainStrategies[i]).withdraw(
                    amountNeeded
                );
                uint256 witdrawed = token.balanceOf(address(this)) -
                    balanceBefore;
                vaultBalance += witdrawed;

                if (loss > 0) {
                    value -= loss;
                    totalLoss += loss;
                    _reportLoss(OnChainStrategies[i], loss);
                }
                strategies[OnChainStrategies[i]].totalDebt -= witdrawed;
                totalDebt -= witdrawed;
                emit StrategyWithdrawnSome(
                    OnChainStrategies[i],
                    strategies[OnChainStrategies[i]].totalDebt,
                    loss
                );
            }
            if (value > vaultBalance) {
                value = vaultBalance;
                // sharesForAmount is another function need to check
                shares = _issueSharesForAmount(msg.sender, value + totalLoss);
            }
            if (totalLoss > (maxLoss * (value + totalLoss)) / MAX_BPS)
                revert Vault__UnacceptableLoss();
        }
        _burn(msg.sender, shares);
        //Burn eq
        // ERC20Upgradeable(address(this))._totalSupply -= shares;
        // ERC20Upgradeable(address(this))._balances[msg.sender] -= shares;
        // emit Transfer(msg.sender, address(0), shares);
        //
        token.safeTransfer(recipient, value);
        emit Withdraw(recipient, shares, value);
        return value;
    }

    function pricePerShare() external view returns (uint256) {
        return _shareValue(10 ** decimals());
    }

    function revokeStrategy(address _strategy) external onlyAuthorized {
        _revokeStrategy(_strategy);
    }

    function revokeStrategy() external {
        require(msg.sender == governance || msg.sender == owner() || msg.sender == OnChainStrategies[strategyPositionInArray[msg.sender]], "notAuthorized");
        _revokeStrategy(msg.sender);
    }

    function updateStrategyDebtRatio(
        address _strategy,
        uint256 _debtRatio
    ) external onlyAuthorized {
        if (strategies[_strategy].activation == 0)
            revert Vault__InactiveStrategy();

        totalDebtRatio -= strategies[_strategy].debtRatio;
        strategies[_strategy].debtRatio = _debtRatio;
        if (totalDebtRatio + _debtRatio > MAX_BPS) revert Vault__V6();
        totalDebtRatio += _debtRatio;
    }

    function migrateStrategy(
        address _oldStrategy,
        address _newStrategy
    ) external onlyAuthorized {
        if (_newStrategy == address(0)) revert Vault__V7();
        if (strategies[_oldStrategy].activation == 0) revert Vault__V8();
        if (strategies[_newStrategy].activation > 0) revert Vault__V9();
        StrategyParams memory params = strategies[_oldStrategy];
        _revokeStrategy(_oldStrategy);
        totalDebtRatio += params.debtRatio;
        
        strategies[_newStrategy] = StrategyParams({
            activation: params.lastReport,
            debtRatio: params.debtRatio,
            totalDebt: params.totalDebt,
            totalGain: 0,
            totalLoss: 0,
            lastReport: params.lastReport,
            performanceFee: params.performanceFee
        });
        // strategies[_oldStrategy].debtRatio = 0;
        strategies[_oldStrategy].totalDebt = 0;

        IBaseStrategy(_oldStrategy).migrate(_newStrategy);
        OnChainStrategies[strategyPositionInArray[_oldStrategy]] = _newStrategy;
        strategyPositionInArray[_newStrategy] = strategyPositionInArray[
            _oldStrategy
        ];
        strategyPositionInArray[_oldStrategy] = 0;
    }

    function _deposit(
        uint256 _amount,
        address _recipient
    ) internal returns (uint256) {
        if (emergencyShutdown) revert Vault__V13();
        uint256 shares = _issueSharesForAmount(_recipient, _amount);
        token.safeTransferFrom(msg.sender, address(this), _amount);
        return shares;
    }

    function report(
        uint256 _gain,
        uint256 _loss,
        uint256 _debtPayment
    ) external returns (uint256) {
        if (strategies[msg.sender].activation == 0) revert Vault__V14();

        if (_loss > 0) {
            _reportLoss(msg.sender, _loss);
        }
        strategies[msg.sender].totalGain += _gain;
        uint256 credit = _creditAvailable(msg.sender);

        
        uint256 debt = _debtOutstanding(msg.sender);
        uint256 debtPayment = Math.min(debt, _debtPayment);

        if (debtPayment > 0) {
            strategies[msg.sender].totalDebt -= debtPayment;
            totalDebt -= debtPayment;
            debt -= debtPayment;
        }

        if (credit > 0) {
            strategies[msg.sender].totalDebt += credit;
            totalDebt += credit;
        }

        uint256 totalAvail = _gain + debtPayment;
        console.log(totalAvail, credit);
        if (totalAvail < credit) {
            console.log("INSIDE TRANSFER",credit - totalAvail);
            token.safeTransfer(msg.sender, credit - totalAvail);
        } else if (totalAvail > credit) {
            console.log("INSIDE TRANSFER",totalAvail - credit);
            token.safeTransferFrom(
                msg.sender,
                address(this),
                totalAvail - credit
            );
        }

        strategies[msg.sender].lastReport = block.timestamp;

        StrategyParams memory params = strategies[msg.sender];
        emit StrategyReported(
            msg.sender,
            _gain,
            _loss,
            _debtPayment,
            params.totalGain,
            params.totalLoss,
            params.totalDebt,
            credit,
            params.debtRatio
        );
        if (strategies[msg.sender].debtRatio == 0 || emergencyShutdown) {
            return IBaseStrategy(msg.sender).estimatedTotalAssets();
        } else {
            return debt;
        }
    }

    function _reportLoss(address _strategy, uint256 _loss) internal {
        if (strategies[_strategy].totalDebt < _loss) revert Vault__V15();
        
        if (totalDebtRatio != 0) {
            uint256 ratioChange = Math.min(_loss * totalDebtRatio / totalDebt, strategies[_strategy].debtRatio);
            strategies[_strategy].debtRatio -= ratioChange;
            totalDebtRatio -= ratioChange;
        }
        strategies[_strategy].totalLoss += _loss;
        strategies[_strategy].totalDebt -= _loss;
        totalDebt -= _loss;
    }

    function _shareValue(uint256 _shares) internal view returns (uint256) {
        if (totalSupply() == 0) {
            return _shares;
        }
        return (_shares * totalAssets()) / totalSupply();
    }

    function _issueSharesForAmount(
        address _to,
        uint256 _amount
    ) internal returns (uint256) {
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount * totalSupply()) / totalAssets();
        }
        if (shares == 0) revert Vault__V17();
        _mint(_to, shares);
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

        uint256 vaultDebtLimit = totalDebtRatio * totalAssets() / MAX_BPS;
        uint256 vaultTotalDebt = totalDebt;

        if (strategyDebtLimit <= strategyTotalDebt) {
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

    receive() external payable {}
}
