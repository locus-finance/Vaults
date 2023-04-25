// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract BaseVaultProxy is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    uint256[] private __gap;

    function initialize(bytes memory _data) public initializer {
        // (a, b, c ...) = abi.decode(_data);
        __Ownable_init();
        _transferOwnership(_msgSender());
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
