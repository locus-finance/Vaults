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

    async function dealWantToAddress(address, want) {
        const ethWhaleAddress = "0x00000000219ab540356cbb839cbe05303d7705fa";
        const usdcWhaleAddress = "0xf646d9B7d20BABE204a89235774248BA18086dae";

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [usdcWhaleAddress],
        });
        const usdcWhale = await ethers.getSigner(usdcWhaleAddress);

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [ethWhaleAddress],
        });
        const ethWhale = await ethers.getSigner(ethWhaleAddress);

        await ethWhale.sendTransaction({
            to: usdcWhale.address,
            value: utils.parseEther("1"),
        });

        await want
            .connect(usdcWhale)
            .transfer(address, utils.parseUnits("1000000", 6));
    }

    it("should deploy strategy", async function () {
        const { vault, strategy } = await loadFixture(
            deployContractAndSetVariables
        );
        expect(await strategy.vault()).to.equal(vault.address);

        const ethToWant = await strategy.ethToWant(utils.parseEther("1.0"));
        console.log("ethToWant", utils.formatUnits(ethToWant, 6));

        const crvToWant = await strategy.crvToWant(utils.parseEther("1.0"));
        console.log("crvToWant", utils.formatUnits(crvToWant, 6));

        const yCrvToWant = await strategy.yCrvToWant(
            utils.parseEther("10000.0")
        );
        console.log("yCrvToWant", utils.formatUnits(yCrvToWant, 6));

        const stYCrvToWant = await strategy.stYCRVToWant(
            utils.parseEther("10000.0")
        );
        console.log("stYCrvToWant", utils.formatUnits(stYCrvToWant, 6));
    });

    it("test buying tokens", async function () {
        const { whale, want, strategy } = await loadFixture(
            deployContractAndSetVariables
        );
        await dealWantToAddress(strategy.address, want);
        await strategy.connect(whale).testPosition(0);
        await strategy.connect(whale).exitPosition(0);
    });
});
