const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("BaseVault", function () {
    async function deployContractAndSetVariables() {
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

    it('should set the symbol correctly', async function () {
        const { vault, symbol } = await loadFixture(deployContractAndSetVariables);
        expect(await vault.symbol()).to.equal(symbol);
    });

    it('should set the name correctly', async function () {
        const { vault, name } = await loadFixture(deployContractAndSetVariables);
        expect(await vault.name()).to.equal(name);
    });

    it('should set the token correctly', async function () {
        const { vault, token } = await loadFixture(deployContractAndSetVariables);
        expect(await vault.token()).to.equal(token.address);
    });

    it('should set the treasury correctly', async function () {
        const { vault, token, treasury } = await loadFixture(deployContractAndSetVariables);
        expect(await vault.rewards()).to.equal(treasury.address);
    });

    it('should receive deposit', async function () {
        const { vault, whale, token } = await loadFixture(deployContractAndSetVariables);
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
        const { vault, whale, token } = await loadFixture(deployContractAndSetVariables);
        await vault['setDepositLimit(uint256)'](ethers.utils.parseEther('0.01'));
        await expect(
            vault.connect(whale)['deposit(uint256)'](ethers.utils.parseEther('1'))
        ).to.be.reverted;
        // @TODO test with active strategy
        expect(await vault.availableDepositLimit()).to.equal(ethers.utils.parseEther('0.01'));
    });

    it('should withdraw', async function () {
        const { vault, whale, token } = await loadFixture(deployContractAndSetVariables);
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
        const { vault, deployer, governance } = await loadFixture(deployContractAndSetVariables);

        await vault['setGovernance(address)'](governance.address);
        expect(await vault.governance()).to.equal(deployer.address);

        await vault.connect(governance)['acceptGovernance()']();
        expect(await vault.governance()).to.equal(governance.address);
    });

    it('should add and revoke strategy', async function () {
        const { vault, deployer, governance } = await loadFixture(deployContractAndSetVariables);

        const TestStrategy = await ethers.getContractFactory('TestStrategy');
        const strategy = await TestStrategy.connect(deployer).deploy(vault.address);
        await strategy.deployed();

        await vault['addStrategy(address,uint256,uint256,uint256,uint256)'](
            strategy.address,
            80,
            ethers.utils.parseEther("1"),
            ethers.utils.parseEther("10000"),
            100,
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
        const { vault, deployer, whale, token } = await loadFixture(deployContractAndSetVariables);

        const amount = ethers.utils.parseEther('1');
        await token.connect(whale).approve(vault.address, amount);
        await vault.connect(whale)['deposit(uint256)'](amount);

        expect(await vault.maxAvailableShares()).to.equal(amount);
    });

    it('should be able to withdraw part of assets when strategy is active but not in withdrawal queue', async function () {
        const { vault, deployer, whale, token } = await loadFixture(deployContractAndSetVariables);

        const TestStrategy = await ethers.getContractFactory('TestStrategy');
        const strategy = await TestStrategy.connect(deployer).deploy(vault.address);
        await strategy.deployed();

        await vault['addStrategy(address,uint256,uint256,uint256,uint256)'](
            strategy.address,
            8000,
            ethers.utils.parseEther("0.001"),
            ethers.utils.parseEther("10000"),
            100,
        );

        await vault.removeStrategyFromQueue(strategy.address);

        const amount = ethers.utils.parseEther('1');
        await token.connect(whale).approve(vault.address, amount);
        await vault.connect(whale)['deposit(uint256)'](amount);

        await strategy.harvest();

        expect(await vault.maxAvailableShares()).to.equal(ethers.utils.parseEther('0.2'));
    });

    it('should be able to withdraw all assets when strategy is active and in withdrawal queue', async function () {
        const { vault, deployer, whale, token } = await loadFixture(deployContractAndSetVariables);

        const TestStrategy = await ethers.getContractFactory('TestStrategy');
        const strategy = await TestStrategy.connect(deployer).deploy(vault.address);
        await strategy.deployed();

        await vault['addStrategy(address,uint256,uint256,uint256,uint256)'](
            strategy.address,
            8000,
            ethers.utils.parseEther("0.001"),
            ethers.utils.parseEther("10000"),
            100,
        );

        const amount = ethers.utils.parseEther('1');
        await token.connect(whale).approve(vault.address, amount);
        await vault.connect(whale)['deposit(uint256)'](amount);

        await strategy.harvest();

        expect(await vault.maxAvailableShares()).to.equal(amount);
    });
});
