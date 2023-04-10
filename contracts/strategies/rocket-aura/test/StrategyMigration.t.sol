// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;
import "forge-std/console.sol";

import {StrategyFixture} from "./utils/StrategyFixture.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// NOTE: if the name of the strat or file changes this needs to be updated
import {Strategy} from "../Strategy.sol";

contract StrategyMigrationTest is StrategyFixture {
    function setUp() public override {
        super.setUp();
    }

    // TODO: Add tests that show proper migration of the strategy to a newer one
    // Use another copy of the strategy to simmulate the migration
    // Show that nothing is lost.
    function testMigration(uint256 _amount) public {
        IERC20 balancerRewardToken = IERC20(0xba100000625a3754423978a60c9317c58a424e3D);
        IERC20 auraRewardToken = IERC20(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF);
        uint256 amountOfTokensToDeal =  10000e18;


        vm.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        deal(address(want), user, _amount);

        // Deposit to the vault and harvest
        vm.prank(user);
        want.approve(address(vault), _amount);
        vm.prank(user);
        vault.deposit(_amount);
        skip(1);
        vm.prank(strategist);
        strategy.harvest();

        deal(address(balancerRewardToken), address(strategy), amountOfTokensToDeal);
        deal(address(auraRewardToken), address(strategy), amountOfTokensToDeal);

        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

        // Migrate to a new strategy
        vm.prank(strategist);
        Strategy newStrategy = Strategy(deployStrategy(address(vault)));
        vm.prank(gov);
        vault.migrateStrategy(address(strategy), address(newStrategy));
        assertRelApproxEq(newStrategy.estimatedTotalAssets(), _amount, DELTA);

        assertApproxEq(balancerRewardToken.balanceOf(address(newStrategy)), amountOfTokensToDeal, 0);
        assertApproxEq(auraRewardToken.balanceOf(address(newStrategy)), amountOfTokensToDeal, 0);
    }
}
