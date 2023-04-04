const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("BaseVault", function () {
    async function deployContractAndSetVariables() {
        const [deployer, whale] = await ethers.getSigners();    
        
        const governance = deployer.address;
        const treasury = deployer.address;
        const name = "ETH Vault";
        const symbol = "vETH";

        const Token = await hre.ethers.getContractFactory("Token");
        const token = await Token.deploy();
        await token.deployed();
        await token.transfer(whale.address, ethers.utils.parseEther('10000'));

        const BaseVault = await ethers.getContractFactory('BaseVault');
        const vault = await BaseVault.deploy();
        await vault.deployed();

        await vault['initialize(address,address,address,string,string)'](token.address, governance, treasury, name, symbol);
        await vault['setDepositLimit(uint256)'](ethers.utils.parseEther('10000'))

        return { vault, deployer, symbol, name, whale, token };
    }

    it('should deploy and set the symbol correctly', async function () {
        const { vault, symbol } = await loadFixture(deployContractAndSetVariables);
        expect(await vault.symbol()).to.equal(symbol);
    });

    it('should deploy and set the name correctly', async function () {
        const { vault, name } = await loadFixture(deployContractAndSetVariables);
        expect(await vault.name()).to.equal(name);
    });

    it('should deploy and set the token correctly', async function () {
        const { vault, token } = await loadFixture(deployContractAndSetVariables);
        expect(await vault.token()).to.equal(token.address);
    });

    it('should deploy and receive deposit', async function () {
        const { vault, whale, token } = await loadFixture(deployContractAndSetVariables);
        await token.connect(whale).approve(vault.address, ethers.utils.parseEther('1'));
        await expect(
            () => vault.connect(whale)['deposit(uint256)'](ethers.utils.parseEther('1'))
        ).to.changeTokenBalances(
            token,
            [whale, vault],
            [ethers.utils.parseEther('-1'), ethers.utils.parseEther('1')]
        );
    });

    it('should deploy and withdraw', async function () {
        const { vault, whale, token } = await loadFixture(deployContractAndSetVariables);
        await token.connect(whale).approve(vault.address, ethers.utils.parseEther('1'));
        await vault.connect(whale)['deposit(uint256)'](ethers.utils.parseEther('1'));
        await expect(
            () => vault.connect(whale)['withdraw(uint256)'](ethers.utils.parseEther('1'))
        ).to.changeTokenBalances(
            token,
            [vault, whale],
            [ethers.utils.parseEther('-1'), ethers.utils.parseEther('1')]
        );
    });
});
