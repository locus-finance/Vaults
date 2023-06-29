// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

import "../integrations/aura/ICvx.sol";

/// @notice Used for calculating rewards.
/// @dev This implementation is taken from CVX's contract (https://etherscan.io/address/0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B#code).
library CVXRewardsMath {
    uint32 internal constant TWAP_RANGE_SECS = 1800;
    address internal constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant CVX_CRV_UNI_V3_POOL =
        0x645c3A387b8633dF1D4D71CA4b50D27233Bcb887;

    using SafeMath for uint256;

    function convertCrvToCvx(uint256 _amount) internal view returns (uint256) {
        uint256 reductionPerCliff = ICvx(CVX).reductionPerCliff();
        uint256 supply = ICvx(CVX).totalSupply();
        uint256 totalCliffs = ICvx(CVX).totalCliffs();
        uint256 maxSupply = ICvx(CVX).maxSupply();

        uint256 cliff = supply.div(reductionPerCliff);
        if (cliff < totalCliffs) {
            uint256 reduction = totalCliffs.sub(cliff);
            _amount = _amount.mul(reduction).div(totalCliffs);

            uint256 amtTillMax = maxSupply.sub(supply);
            if (_amount > amtTillMax) {
                _amount = amtTillMax;
            }
        }
        return _amount;
    }

    function cvxToCrv(uint256 cvxTokens) internal view returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            CVX_CRV_UNI_V3_POOL,
            TWAP_RANGE_SECS
        );
        return
            OracleLibrary.getQuoteAtTick(
                meanTick,
                uint128(cvxTokens),
                CVX,
                CRV
            );
    }
}
