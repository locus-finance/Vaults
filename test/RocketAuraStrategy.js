const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

describe("RocketAuraStrategy", function () {
    async function deployContractAndSetVariables() {
        const [deployer, governance, treasury] = await ethers.getSigners();
        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: ["0xd8da6bf26964af9d7eed9e03e53415d37aa96045"],
        });
        const whale = await ethers.getSigner("0xd8da6bf26964af9d7eed9e03e53415d37aa96045"); // vitalik.eth
        
        const name = "ETH Vault";
        const symbol = "vETH";

        token = await hre.ethers.getContractAt(
            IERC20_SOURCE, 
            "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", // WETH
        );

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

        return { vault, deployer, symbol, name, token, whale, governance, treasury };
    }

    it('should deploy strategy', async function () {
        const { vault, symbol, token, whale } = await loadFixture(deployContractAndSetVariables);
        console.log(await token.balanceOf(whale.address));
        console.log(await token.balanceOf(vault.address));
        await token.connect(whale).approve(vault.address, ethers.utils.parseEther("1"));
        await token.connect(whale).transfer(vault.address, ethers.utils.parseEther("1"));
        console.log(await token.balanceOf(whale.address));
        console.log(await token.balanceOf(vault.address));
        expect(await vault.symbol()).to.equal(symbol);
    });
});
