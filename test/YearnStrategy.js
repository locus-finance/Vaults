const {
    loadFixture,
    mine,
} = require("@nomicfoundation/hardhat-network-helpers");
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { expect } = require("chai");
const { BigNumber, utils } = require("ethers");
const { ethers } = require("hardhat");

const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

describe.only("YearnStrategy", function () {
    async function deployContractAndSetVariables() {
        const [deployer, governance, treasury, whale] =
            await ethers.getSigners();
        const USDC_ADDRESS = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
        const want = await ethers.getContractAt(IERC20_SOURCE, USDC_ADDRESS);

        const name = "USDC Vault";
        const symbol = "vUSDC";
        const Vault = await ethers.getContractFactory("Vault");
        const vault = await Vault.deploy();
        await vault.deployed();

        await vault["initialize(address,address,address,string,string)"](
            want.address,
            deployer.address,
            treasury.address,
            name,
            symbol
        );
        await vault["setDepositLimit(uint256)"](
            ethers.utils.parseEther("10000")
        );

        const YearnStrategy = await ethers.getContractFactory("YearnStrategy");
        const strategy = await YearnStrategy.deploy(vault.address);
        await strategy.deployed();

        await vault["addStrategy(address,uint256,uint256,uint256,uint256)"](
            strategy.address,
            10000,
            0,
            ethers.utils.parseEther("10000"),
            0
        );

        return {
            vault,
            deployer,
            symbol,
            name,
            want,
            whale,
            governance,
            treasury,
            strategy,
            want,
        };
    }

    it("should deploy strategy", async function () {
        const { vault, strategy } = await loadFixture(
            deployContractAndSetVariables
        );
        expect(await strategy.vault()).to.equal(vault.address);

        const ethToWant = await strategy.ethToWant(utils.parseEther("0.5"));
        console.log("ethToWant", utils.formatUnits(ethToWant, 6));

        const crvToWant = await strategy.crvToWant(utils.parseEther("1.0"));
        console.log("crvToWant", utils.formatUnits(crvToWant, 6));

        const yCrvToWant = await strategy.yCrvToWant(utils.parseEther("1.0"));
        console.log("yCrvToWant", utils.formatUnits(yCrvToWant, 6));
    });
});
