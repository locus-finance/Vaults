// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../integrations/gmx/IRewardRouterV2.sol";
import "../integrations/gmx/IGlpManager.sol";
import "../integrations/camelot/IPositionHelper.sol";
import "../integrations/gainsnetwork/IGNSStakingV6_2.sol";

interface IArbitrumDeFiStrategy {
    function claimRewards() external view returns (bool);

    function slippage() external view returns (uint256);

    function mintRouter() external view returns (IRewardRouterV2);

    function glpManager() external view returns (IGlpManager);

    function balanceOfWant() external view returns (uint256);

    function getGMXTvl() external view returns (uint256);

    function setSlippage(uint256 _slippage) external;

    function buyTokens(
        address baseToken,
        address[] memory tokens,
        uint256[] memory amount
    ) external payable;

    function buyToken(
        address baseToken,
        address token,
        uint256 amount
    ) external payable;

    function setDex(address newFactory, address newAmm) external;

    function setFeesLevels(uint24[] memory newFees) external;
}
