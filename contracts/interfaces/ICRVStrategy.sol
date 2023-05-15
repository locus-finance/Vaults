// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.12;

import "../integrations/balancer/IBalancerPriceOracle.sol";
import "../integrations/curve/ICurve.sol";

interface ICRVStrategy {
    function slippage() external view returns (uint256);

    function setSlippage(uint256 slippage) external;

    function balanceOfWant() external view returns (uint256);

    function balanceOfStakedYCrv() external view returns (uint256);

    function balanceOfYCrv() external view returns (uint256);

    function crvToWant(uint256 crvTokens) external view returns (uint256);

    function yCrvToWant(uint256 yCRVTokens) external view returns (uint256);

    function stYCRVToWant(uint256 stTokens) external view returns (uint256);

    function wantToStYCrv(uint256 wantTokens) external view returns (uint256);

    function wantToYCrv(uint256 wantTokens) external view returns (uint256);
}
