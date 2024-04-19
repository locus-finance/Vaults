// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ILocusVault} from "../../interfaces/separatedVault/ILocusVault.sol";

contract LocusVaultToken is
    Initializable,
    ERC20Upgradeable,
    UUPSUpgradeable,
    AccessControlUpgradeable
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    ILocusVault public currentVault;

    function initialize(
        address _admin,
        address _vault,
        string memory name,
        string memory symbol
    ) external initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ERC20_init(name, symbol);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(VAULT_ROLE, _vault);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        currentVault = ILocusVault(_vault);
    }

    function mint(address to, uint256 amount) external onlyRole(VAULT_ROLE) {
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) external onlyRole(VAULT_ROLE) {
        _burn(to, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return IERC20Metadata(address(currentVault.token())).decimals();
    }

    function dispatch(address[] memory to, uint256[] memory amount) external {
        uint256 len = to.length;
        for (uint256 i; i < len; i++) {
            _transfer(_msgSender(), to[i], amount[i]);
        }
    }

    function setCurrentVault(address newVault) external onlyRole(ADMIN_ROLE) {
        _revokeRole(VAULT_ROLE, address(currentVault));
        currentVault = ILocusVault(newVault);
        _grantRole(VAULT_ROLE, newVault);
    }

    function pricePerShare() external view returns (uint256 pps) {
        pps = currentVault.pricePerShare();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(ADMIN_ROLE) {}
}
