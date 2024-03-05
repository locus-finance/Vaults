// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../contracts/interfaces/IBaseVault.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SimpleMigration is Ownable {
    IBaseVault public vaultV1;
    IBaseVault public vaultV2;

    constructor(address _vaultV2, address _vaultV1) {
        setVaults(_vaultV2, _vaultV1);
    }

    function setVaults(address _vaultV2, address _vaultV1) public onlyOwner {
        vaultV1 = IBaseVault(_vaultV1);
        vaultV2 = IBaseVault(_vaultV2);
        vaultV1.token().approve(address(vaultV2), type(uint256).max);
    }

    function migrateUser(address user, uint256 amount) external onlyOwner {
        IERC20(address(vaultV1)).transferFrom(user, address(this), amount);
        vaultV1.withdraw();
        IERC20 token = vaultV1.token();
        vaultV2.deposit(token.balanceOf(address(this)), user);
    }
}
