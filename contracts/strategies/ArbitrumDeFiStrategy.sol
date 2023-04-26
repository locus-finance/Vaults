// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {BaseStrategyInitializable, StrategyParams} from "./../BaseStrategy.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// import "./interfaces/ "

contract ArbitrumDeFiStrategy is BaseStrategyInitializable {
    using SafeERC20 for IERC20;
    using Address for address;

    bool public claimRewards = true; // claim rewards when withdrawAndUnwrap

    constructor(address _vault) BaseStrategyInitializable(_vault) {
        //want.approve(address(...), type(uint256).max);
        //IGMX(gmx).approve(..., type(uint256).max);
        //ICamelot(glp).approve(address(...), type(uint256).max);
        //IERC20(camelot).approve(address(...), type(uint256).max);
    }

    function name() external view override returns (string memory) {
        return "ArbitrumDeFi";
    }

    function estimatedTotalAssets()
        public
        view
        override
        returns (uint256 _wants)
    {
        return _wants;
    }

    function prepareReturn(
        uint256 _debtOutstanding
    )
        internal
        override
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    {}

    function adjustPosition(uint256 _debtOutstanding) internal override {}

    function withdrawSome(uint256 _amountNeeded) internal {}

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(
        uint256 _amtInWei
    ) public view virtual override returns (uint256) {
        return _amtInWei;
    }

    function liquidateAllPositions() internal override returns (uint256) {}

    function liquidatePosition(
        uint256 _amountNeeded
    ) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {}

    function prepareMigration(address _newStrategy) internal override {
        //
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](4);
        ///
        return protected;
    }
}
