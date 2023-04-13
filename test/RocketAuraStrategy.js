const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

describe("RocketAuraStrategy", function () {
    async function deployContractAndSetVariables() {
        const [deployer, governance, treasury, whale] = await ethers.getSigners();
        const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
        const want = await ethers.getContractAt("IWETH", WETH_ADDRESS);
        await want.connect(whale).deposit({value: ethers.utils.parseEther("10")});

        const name = "ETH Vault";
        const symbol = "vETH";
        const BaseVault = await ethers.getContractFactory('BaseVault');
        const vault = await BaseVault.deploy();
        await vault.deployed();
        await hre.network.provider.send("evm_mine");

        await vault['initialize(address,address,address,string,string)'](
            want.address,
            deployer.address,
            treasury.address,
            name,
            symbol
        );
        await vault['setDepositLimit(uint256)'](ethers.utils.parseEther('10000'))

        const RocketAuraStrategy = await ethers.getContractFactory('RocketAuraStrategy');
        const strategy = await RocketAuraStrategy.deploy(vault.address);
        await strategy.deployed();

        await vault['addStrategy(address,uint256,uint256,uint256,uint256)'](
            strategy.address, 
            10000, 
            0, 
            ethers.utils.parseEther('10000'), 
            0
        );

        return { vault, deployer, symbol, name, want, whale, governance, treasury, strategy, want };
    }

    it('should deploy strategy', async function () {
        const { vault, strategy } = await loadFixture(deployContractAndSetVariables);
        expect(await strategy.vault()).to.equal(vault.address);
    });

    it('should operate', async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(deployContractAndSetVariables);

        auraBRethStable = await hre.ethers.getContractAt(
            IERC20_SOURCE, 
            "0x001B78CEC62DcFdc660E06A91Eb1bC966541d758", // WETH
        );
        
        const balanceBefore = await want.balanceOf(whale.address);
        
        await want.connect(whale).approve(vault.address, ethers.utils.parseEther('10'));
        await vault.connect(whale)['deposit(uint256)'](ethers.utils.parseEther('10'));

        expect(await want.balanceOf(vault.address)).to.equal(ethers.utils.parseEther('10'));

        await strategy.connect(deployer).harvest();
        expect(await strategy.estimatedTotalAssets())
        .to.be.closeTo(ethers.utils.parseEther('10'), ethers.utils.parseEther('0.02'));

        console.log("await vault.balanceOf(whale.address)");
        console.log(await vault.balanceOf(whale.address));
        console.log("await want.balanceOf(whale.address)");
        console.log(await want.balanceOf(whale.address));
        await strategy.connect(deployer).tend();

        await vault.connect(whale)['withdraw(uint256)'](ethers.utils.parseEther('10'));

        // expect(await want.balanceOf(whale.address))
        // .to.be.closeTo(balanceBefore, ethers.utils.parseEther('1.5'));
        console.log("await vault.balanceOf(whale.address)");
        console.log(await vault.balanceOf(whale.address));
        console.log("await want.balanceOf(whale.address)");
        console.log(await want.balanceOf(whale.address));
    });
});
