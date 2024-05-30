// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

abstract contract StrategyHelper {
    error SelfSenderOnly();

    modifier onlySelf {
        if (msg.sender != address(this)) {
            revert SelfSenderOnly();
        }
        _;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[45] private __gap;
}