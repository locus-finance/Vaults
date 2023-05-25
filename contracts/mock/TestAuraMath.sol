// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import "../utils/AuraMath.sol";

contract TestAuraMath {
    function convertCrvToCvx(uint256 _amount) public view returns (uint256) {
        return AuraRewardsMath.convertCrvToCvx(_amount);
    }
}
