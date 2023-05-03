// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import { BaseStrategyInitializable, StrategyParams } from "../BaseStrategy.sol";

contract YearnStrategy is BaseStrategyInitializable {
    constructor(address _vault) BaseStrategyInitializable(_vault) {}

    function name() external pure override returns (string memory) {
        return "YearnStrategy";
    }

    function ethToWant(
        uint256 _amtInWei
    ) public view override returns (uint256) {
        return _amtInWei;
    }

    function estimatedTotalAssets() public view override returns (uint256) {}

    function prepareReturn(
        uint256 _debtOutstanding
    )
        internal
        override
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    {}

    function adjustPosition(uint256 _debtOutstanding) internal override {}

    function liquidateAllPositions() internal override returns (uint256) {}

    function liquidatePosition(
        uint256 _amountNeeded
    ) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {}

    function prepareMigration(address _newStrategy) internal override {}

    function protectedTokens()
        internal
        pure
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](0);
        return protected;
    }
}
