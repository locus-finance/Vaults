const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("BaseVault", function () {
    async function deployVaultAndSetVariables() {
        const [deployer, whale, governance, treasury] = await ethers.getSigners();
        
        const name = "ETH Vault";
        const symbol = "vETH";

        const Token = await hre.ethers.getContractFactory("Token");
        const token = await Token.deploy();
        await token.deployed();
        await token.transfer(whale.address, ethers.utils.parseEther('10000'));

        const BaseVault = await ethers.getContractFactory('BaseVault');
        const vault = await BaseVault.deploy();
        await vault.deployed();

        await vault['initialize(address,address,address,string,string)'](
            token.address,
            deployer.address,
            treasury.address,
            name,
            symbol
        );
        await vault['setDepositLimit(uint256)'](ethers.utils.parseEther('10000'))

        return { vault, deployer, symbol, name, whale, token, governance, treasury };
    }

    async function deployVaultAndStrategy() {
        const [deployer, whale, governance, treasury] = await ethers.getSigners();
        
        const name = "ETH Vault";
        const symbol = "vETH";

        const Token = await hre.ethers.getContractFactory("Token");
        const token = await Token.deploy();
        await token.deployed();
        await token.transfer(whale.address, ethers.utils.parseEther('10000'));

        const BaseVault = await ethers.getContractFactory('BaseVault');
        const vault = await BaseVault.deploy();
        await vault.deployed();

        await vault['initialize(address,address,address,string,string)'](
            token.address,
            deployer.address,
            treasury.address,
            name,
            symbol
        );
        await vault['setDepositLimit(uint256)'](ethers.utils.parseEther('10000'))

        const TestStrategy = await ethers.getContractFactory('TestStrategy');
        const strategy = await TestStrategy.connect(deployer).deploy(vault.address);
        await strategy.deployed();

        await vault['addStrategy(address,uint256,uint256,uint256,uint256)'](
            strategy.address,
            8000,
            1,
            ethers.utils.parseEther("10000"),
            0,
        );
        return { vault, deployer, symbol, name, whale, token, governance, treasury, strategy };
    }

    it('should set the symbol correctly', async function () {
        const { vault, symbol } = await loadFixture(deployVaultAndSetVariables);
        expect(await vault.symbol()).to.equal(symbol);
    });

    it('should set the name correctly', async function () {
        const { vault, name } = await loadFixture(deployVaultAndSetVariables);
        expect(await vault.name()).to.equal(name);
    });

    it('should set the token correctly', async function () {
        const { vault, token } = await loadFixture(deployVaultAndSetVariables);
        expect(await vault.token()).to.equal(token.address);
    });

    it('should set the treasury correctly', async function () {
        const { vault, token, treasury } = await loadFixture(deployVaultAndSetVariables);
        expect(await vault.rewards()).to.equal(treasury.address);
    });

    it('should receive deposit', async function () {
        const { vault, whale, token } = await loadFixture(deployVaultAndSetVariables);
        const amount = ethers.utils.parseEther('1');
        await token.connect(whale).approve(vault.address, amount);
        await expect(
            () => vault.connect(whale)['deposit(uint256)'](amount)
        ).to.changeTokenBalances(
            token,
            [whale, vault],
            [ethers.utils.parseEther('-1'), amount]
        );
        expect(await vault.balanceOf(whale.address)).to.equal(amount);
        expect(await vault.totalSupply()).to.equal(amount);
    });

    it('should not receive deposit over limit', async function () {
        const { vault, whale, token } = await loadFixture(deployVaultAndSetVariables);
        await vault['setDepositLimit(uint256)'](ethers.utils.parseEther('0.01'));
        await expect(
            vault.connect(whale)['deposit(uint256)'](ethers.utils.parseEther('1'))
        ).to.be.reverted;
        // @TODO test with active strategy
        expect(await vault.availableDepositLimit()).to.equal(ethers.utils.parseEther('0.01'));
    });

    it('should not receive any deposit when deposit limit is zero', async function () {
        const { vault, whale, token } = await loadFixture(deployVaultAndSetVariables);
        await vault['setDepositLimit(uint256)'](0);
        const amount = 1;
        await token.connect(whale).approve(vault.address, amount);
        await expect(
            vault.connect(whale)['deposit(uint256)'](amount)
        ).to.be.reverted;
        expect(await vault.availableDepositLimit()).to.equal(0);
    });

    it('should not receive any deposit when emergency shutdown is active', async function () {
        const { vault, whale, token } = await loadFixture(deployVaultAndSetVariables);
        await vault['setEmergencyShutdown(bool)'](true);
        const amount = ethers.utils.parseEther('1');
        await token.connect(whale).approve(vault.address, amount);
        await expect(
            vault.connect(whale)['deposit(uint256)'](amount)
        ).to.be.reverted;
    });

    it('should not withdraw when no idle and withdrawl queue is empty', async function () {
        const { vault, whale, deployer, token } = await loadFixture(deployVaultAndSetVariables);

        const amount = ethers.utils.parseEther('1');
        await token.connect(whale).approve(vault.address, amount);
        await vault.connect(whale)['deposit(uint256)'](amount);

        const TestStrategy = await ethers.getContractFactory('TestStrategy');
        const strategy = await TestStrategy.connect(deployer).deploy(vault.address);
        await strategy.deployed();

        await vault['addStrategy(address,uint256,uint256,uint256,uint256)'](
            strategy.address,
            10000,
            ethers.utils.parseEther("0.001"),
            ethers.utils.parseEther("10000"),
            0,
        );

        await vault.removeStrategyFromQueue(strategy.address);

        await strategy.harvest();

        await expect(
            () => vault.connect(whale)['withdraw(uint256)'](amount)
        ).to.changeTokenBalances(
            token,
            [vault, whale, strategy],
            [0, 0, 0]
        );

        await expect(
            vault.connect(whale)['withdraw(uint256)'](amount)
        ).to.emit(token, 'Transfer')
        .withArgs(vault.address, whale.address, 0)
        .and.to.emit(vault, 'Transfer')
        .withArgs(whale.address, "0x0000000000000000000000000000000000000000", 0);
    });

    it('should withdraw', async function () {
        const { vault, whale, token } = await loadFixture(deployVaultAndSetVariables);
        const amount = ethers.utils.parseEther('1');
        await token.connect(whale).approve(vault.address, amount);
        await vault.connect(whale)['deposit(uint256)'](amount);
        await expect(
            () => vault.connect(whale)['withdraw(uint256)'](amount)
        ).to.changeTokenBalances(
            token,
            [vault, whale],
            [ethers.utils.parseEther('-1'), amount]
        );
        expect(await vault.balanceOf(whale.address)).to.equal(0);
        expect(await vault.totalSupply()).to.equal(0);
    });

    it('should set governance', async function () {
        const { vault, deployer, governance } = await loadFixture(deployVaultAndSetVariables);

        await vault['setGovernance(address)'](governance.address);
        expect(await vault.governance()).to.equal(deployer.address);

        await vault.connect(governance)['acceptGovernance()']();
        expect(await vault.governance()).to.equal(governance.address);
    });

    it('should add and revoke strategy', async function () {
        const { vault, deployer, governance } = await loadFixture(deployVaultAndSetVariables);

        const TestStrategy = await ethers.getContractFactory('TestStrategy');
        const strategy = await TestStrategy.connect(deployer).deploy(vault.address);
        await strategy.deployed();

        await vault['addStrategy(address,uint256,uint256,uint256,uint256)'](
            strategy.address,
            80,
            ethers.utils.parseEther("1"),
            ethers.utils.parseEther("10000"),
            0,
        );
        let {
            performanceFee,
            activation,
            debtRatio,
            minDebtPerHarvest,
            maxDebtPerHarvest,
            lastReport,
            totalDebt,
            totalGain,
            totalLoss
        } = await vault.strategies(strategy.address);
        expect(debtRatio).to.equal(80);

        await vault['revokeStrategy(address)'](strategy.address);
        ({
            performanceFee,
            activation,
            debtRatio,
            minDebtPerHarvest,
            maxDebtPerHarvest,
            lastReport,
            totalDebt,
            totalGain,
            totalLoss
        } = await vault.strategies(strategy.address));
        expect(debtRatio).to.equal(0);
    });

    it('should be able to withdraw all assets when no active strategy', async function () {
        const { vault, deployer, whale, token } = await loadFixture(deployVaultAndSetVariables);

        const amount = ethers.utils.parseEther('1');
        await token.connect(whale).approve(vault.address, amount);
        await vault.connect(whale)['deposit(uint256)'](amount);

        expect(await vault.maxAvailableShares()).to.equal(amount);
    });

    it('should be able to withdraw part of assets when strategy is active but not in withdrawal queue', async function () {
        const { vault, deployer, whale, token } = await loadFixture(deployVaultAndSetVariables);

        const TestStrategy = await ethers.getContractFactory('TestStrategy');
        const strategy = await TestStrategy.connect(deployer).deploy(vault.address);
        await strategy.deployed();

        await vault['addStrategy(address,uint256,uint256,uint256,uint256)'](
            strategy.address,
            8000,
            ethers.utils.parseEther("0.001"),
            ethers.utils.parseEther("10000"),
            0,
        );

        await vault.removeStrategyFromQueue(strategy.address);

        const amount = ethers.utils.parseEther('1');
        await token.connect(whale).approve(vault.address, amount);
        await vault.connect(whale)['deposit(uint256)'](amount);

        await strategy.harvest();

        expect(await vault.maxAvailableShares()).to.equal(ethers.utils.parseEther('0.2'));
        expect(await vault.pricePerShare()).to.equal(amount);
    });

    it('should be able to withdraw all assets when strategy is active and in withdrawal queue', async function () {
        const { vault, whale, token, strategy } = await loadFixture(deployVaultAndStrategy);

        const amount = ethers.utils.parseEther('1');
        await token.connect(whale).approve(vault.address, amount);
        await vault.connect(whale)['deposit(uint256)'](amount);

        await strategy.harvest();

        expect(await vault.maxAvailableShares()).to.equal(amount);
        expect(await vault.pricePerShare()).to.equal(amount);
    });

    it('should give strategy credit', async function () {
        const { vault, whale, token, strategy } = await loadFixture(deployVaultAndStrategy);

        const amount = ethers.utils.parseEther('1');
        await token.connect(whale).approve(vault.address, amount);
        await vault.connect(whale)['deposit(uint256)'](amount);

        await expect(
            () => strategy.harvest()
        ).to.changeTokenBalances(
            token,
            [strategy, vault],
            [ethers.utils.parseEther('0.8'), ethers.utils.parseEther('-0.8')]
        );
    });

    it('should handle strategy profit', async function () {
        const { vault, whale, token, strategy } = await loadFixture(deployVaultAndStrategy);

        const amount = ethers.utils.parseEther('1');
        await token.connect(whale).approve(vault.address, amount);
        await vault.connect(whale)['deposit(uint256)'](amount);
        
        await strategy.harvest();

        await token.connect(whale).transfer(strategy.address, ethers.utils.parseEther('0.23'));

        await expect(
            () => strategy.harvest()
        ).to.changeTokenBalances(
            token,
            [strategy, vault],
            [ethers.utils.parseEther('-0.23'), ethers.utils.parseEther('0.23')]
        );
    });

    it('should handle strategy loss', async function () {
        const { vault, deployer, whale, token, strategy } = await loadFixture(deployVaultAndStrategy);

        const amount = ethers.utils.parseEther('1');
        await token.connect(whale).approve(vault.address, amount);
        await vault.connect(whale)['deposit(uint256)'](amount);
        
        await strategy.harvest();
        await strategy.connect(deployer)._takeFunds(ethers.utils.parseEther('0.23'));
        await strategy.harvest();
        ({
            performanceFee,
            activation,
            debtRatio,
            minDebtPerHarvest,
            maxDebtPerHarvest,
            lastReport,
            totalDebt,
            totalGain,
            totalLoss
        } = await vault.strategies(strategy.address));
        expect(totalLoss).to.equal(ethers.utils.parseEther('0.23'));
    });
});
