// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;
import "forge-std/console.sol";

import {StrategyFixture} from "./utils/StrategyFixture.sol";
import {Utils} from "./utils/Utils.sol";
import {StrategyParams} from "../interfaces/Vault.sol";
import {IBalancerPool} from "../interfaces/IBalancerPool.sol";
import {IBalancerV2Vault, IAsset} from "../interfaces/IBalancerV2Vault.sol";
import {IAuraRewards} from "../interfaces/IAuraRewards.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StrategyOperationsTest is StrategyFixture {
    // setup is run on before each test
    function setUp() public override {
        // setup vault
        super.setUp();
    }

    function testSetupVaultOK() public {
        console.log("address of vault", address(vault));
        assertTrue(address(0) != address(vault));
        assertEq(vault.token(), address(want));
        assertEq(vault.depositLimit(), type(uint256).max);
    }

    // TODO: add additional check on strat params
    function testSetupStrategyOK() public {
        console.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(address(strategy.vault()), address(vault));
    }

    /// Test Operations
    function testStrategyOperation(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        deal(address(want), user, _amount);

        uint256 balanceBefore = want.balanceOf(address(user));
        vm.prank(user);
        want.approve(address(vault), _amount);
        vm.prank(user);
        vault.deposit(_amount);
        assertRelApproxEq(want.balanceOf(address(vault)), _amount, DELTA);

        skip(3 minutes);
        vm.prank(strategist);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

        // tend
        vm.prank(strategist);
        strategy.tend();

        vm.prank(user);
        vault.withdraw();

        assertRelApproxEq(want.balanceOf(user), balanceBefore, DELTA);
    }

    function testEmergencyExit(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        deal(address(want), user, _amount);

        // Deposit to the vault
        vm.prank(user);
        want.approve(address(vault), _amount);
        vm.prank(user);
        vault.deposit(_amount);
        skip(1);
        vm.prank(strategist);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

        // set emergency and exit
        vm.prank(gov);
        strategy.setEmergencyExit();
        skip(1);
        vm.prank(strategist);
        strategy.harvest();
        assertLt(strategy.estimatedTotalAssets(), _amount);
    }

    function testProfitableHarvesting(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        deal(address(want), user, _amount);

        IERC20 auraToken = IERC20(0x001B78CEC62DcFdc660E06A91Eb1bC966541d758);
        IERC20 balancerToken = IERC20(0x1E19CF2D73a72Ef1332C882F20534B6519Be0276);

        console.log("User wETH balance:", want.balanceOf(address(user)));
        console.log("Vault wETH balance:", want.balanceOf(address(vault)));

        // Deposit to the vault
        console.log("\nUser deposit funds to vault");
        vm.prank(user);
        want.approve(address(vault), _amount);
        vm.prank(user);
        vault.deposit(_amount);

        console.log("User wETH balance:", want.balanceOf(address(user)));
        console.log("Vault wETH balance:", want.balanceOf(address(vault)));

        assertRelApproxEq(want.balanceOf(address(vault)), _amount, DELTA);

        uint256 beforePps = vault.pricePerShare();

        uint256 balancerTokens = balancerToken.balanceOf(address(strategy));
        console.log("Strategy B-rETH-STABLE", balancerTokens);
        uint256 auraTokens = auraToken.balanceOf(address(strategy));
        console.log("Strategy auraB-rETH-STABLE", auraTokens);

        assertEq(balancerTokens, 0);

        console.log("BAL tokens");
        console.log(strategy.balRewards());
        console.log("AURA tokens");
        console.log(strategy.auraRewards(strategy.balRewards()));

        console.log("\nHarvest 1: Send funds through the strategy");
        skip(1);
        vm.prank(strategist);
        strategy.harvest();
        skip(1);

        balancerTokens = balancerToken.balanceOf(address(strategy));
        console.log("Strategy B-rETH-STABLE", balancerTokens);
        auraTokens = auraToken.balanceOf(address(strategy));
        console.log("Strategy auraB-rETH-STABLE", auraTokens);
        assertGt(auraTokens, 0);

        console.log("Strategy total assets", strategy.estimatedTotalAssets());
        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA/3000);

        console.log("BAL tokens");
        console.log(strategy.balRewards());
        console.log("AURA tokens");
        console.log(strategy.auraRewards(strategy.balRewards()));

        uint256 estimatedTotalAssetsBefore = strategy.estimatedTotalAssets();

        console.log("\nSkip 1000 blocks");
        skip(1000);

        console.log("BAL tokens");
        console.log(strategy.balRewards());
        console.log("AURA tokens");
        console.log(strategy.auraRewards(strategy.balRewards()));

        console.log("\nHarvest 2: Realize profit");
        vm.prank(strategist);
        strategy.harvest();

        console.log("BAL tokens");
        console.log(strategy.balRewards());
        console.log("AURA tokens");
        console.log(strategy.auraRewards(strategy.balRewards()));

        console.log("Strategy total assets", strategy.estimatedTotalAssets());
        balancerTokens = balancerToken.balanceOf(address(strategy));
        console.log("Strategy B-rETH-STABLE", balancerTokens);
        auraTokens = auraToken.balanceOf(address(strategy));
        console.log("Strategy auraB-rETH-STABLE", auraTokens);

        assertGt(strategy.estimatedTotalAssets(), estimatedTotalAssetsBefore);
        // uint256 profit = want.balanceOf(address(vault));
        // assertGt(strategy.estimatedTotalAssets() + profit, _amount);
        // assertGt(vault.pricePerShare(), beforePps);
        
    }

    function testChangeDebt(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        deal(address(want), user, _amount);

        // Deposit to the vault and harvest
        vm.prank(user);
        want.approve(address(vault), _amount);
        vm.prank(user);
        vault.deposit(_amount);
        vm.prank(gov);
        vault.updateStrategyDebtRatio(address(strategy), 5_000);

        skip(1);
        vm.prank(strategist);
        strategy.harvest();

        skip(1);
        vm.prank(strategist);
        strategy.harvest();
        uint256 half = uint256(_amount / 2);
        assertRelApproxEq(strategy.estimatedTotalAssets(), half, DELTA/300);

        vm.prank(gov);
        vault.updateStrategyDebtRatio(address(strategy), 10_000);
        skip(1);
        vm.prank(strategist);
        strategy.harvest();
        skip(1);
        vm.prank(strategist);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA/300);

        // In order to pass these tests, you will need to implement prepareReturn.
        // TODO: uncomment the following lines.
        vm.prank(gov);
        vault.updateStrategyDebtRatio(address(strategy), 5_000);
        skip(1);
        vm.prank(strategist);
        strategy.harvest();
        skip(1);
        vm.prank(strategist);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), half, DELTA/300);
    }

    function testProfitableHarvestOnDebtChange(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        deal(address(want), user, _amount);

        // Deposit to the vault
        vm.prank(user);
        want.approve(address(vault), _amount);
        vm.prank(user);
        vault.deposit(_amount);
        assertRelApproxEq(want.balanceOf(address(vault)), _amount, DELTA);

        uint256 beforePps = vault.pricePerShare();

        // Harvest 1: Send funds through the strategy
        skip(1);
        vm.prank(strategist);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

        // TODO: Add some code before harvest #2 to simulate earning yield

        vm.prank(gov);
        vault.updateStrategyDebtRatio(address(strategy), 5_000);

        // In order to pass these tests, you will need to implement prepareReturn.
        // TODO: uncomment the following lines.
        /*
        // Harvest 2: Realize profit
        skip(1);
        vm.prank(strategist);
        strategy.harvest();
        //Make sure we have updated the debt ratio of the strategy
        assertRelApproxEq(
            strategy.estimatedTotalAssets(), 
            _amount / 2, 
            DELTA
        );
        skip(6 hours);

        //Make sure we have updated the debt and made a profit
        uint256 vaultBalance = want.balanceOf(address(vault));
        StrategyParams memory params = vault.strategies(address(strategy));
        //Make sure we got back profit + half the deposit
        assertRelApproxEq(
            _amount / 2 + params.totalGain, 
            vaultBalance, 
            DELTA
        );
        assertGe(vault.pricePerShare(), beforePps);
        */
    }

    function testSweep(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        deal(address(want), user, _amount);

        // Strategy want token doesn't work
        vm.prank(user);
        want.transfer(address(strategy), _amount);
        assertEq(address(want), address(strategy.want()));
        assertGt(want.balanceOf(address(strategy)), 0);

        vm.prank(gov);
        vm.expectRevert("!want");
        strategy.sweep(address(want));

        // Vault share token doesn't work
        vm.prank(gov);
        vm.expectRevert("!shares");
        strategy.sweep(address(vault));

        // TODO: If you add protected tokens to the strategy.
        // Protected token doesn't work
        // vm.prank(gov);
        // vm.expectRevert("!protected");
        // strategy.sweep(strategy.protectedToken());

        uint256 beforeBalance = weth.balanceOf(gov);
        uint256 wethAmount = 1 ether;
        deal(address(weth), user, wethAmount);
        vm.prank(user);
        weth.transfer(address(strategy), wethAmount);
        assertNeq(address(weth), address(strategy.want()));
        assertEq(weth.balanceOf(user), 0);
        vm.prank(gov);
        strategy.sweep(address(weth));
        assertRelApproxEq(
            weth.balanceOf(gov),
            wethAmount + beforeBalance,
            DELTA
        );
    }

    function testTriggers(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        deal(address(want), user, _amount);

        // Deposit to the vault and harvest
        vm.prank(user);
        want.approve(address(vault), _amount);
        vm.prank(user);
        vault.deposit(_amount);
        vm.prank(gov);
        vault.updateStrategyDebtRatio(address(strategy), 5_000);
        skip(1);
        vm.prank(strategist);
        strategy.harvest();

        strategy.harvestTrigger(0);
        strategy.tendTrigger(0);
    }

    function testPlayground() public {
        uint256 strategyBalance = want.balanceOf(address(strategy));
        console.log(strategyBalance);
        console.log(strategy.getBalPrice());
    }
}
