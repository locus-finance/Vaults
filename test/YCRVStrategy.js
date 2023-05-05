const {
    loadFixture,
    mine,
} = require("@nomicfoundation/hardhat-network-helpers");
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { expect } = require("chai");
const { BigNumber, utils } = require("ethers");
const { ethers } = require("hardhat");

const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

describe("YCRVStrategy", function () {
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

        const YCRVStrategy = await ethers.getContractFactory("YCRVStrategy");
        const strategy = await YCRVStrategy.deploy(vault.address);
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

    async function dealWantToAddress(address, want, amountUnscaled = "100") {
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
            .transfer(address, utils.parseUnits(amountUnscaled, 6));
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

    it("should harvest with profit", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );
        await dealWantToAddress(whale.address, want, "1000");

        const balanceBefore = await want.balanceOf(whale.address);

        await want
            .connect(whale)
            ["approve(address,uint256)"](vault.address, balanceBefore);
        await vault.connect(whale)["deposit(uint256)"](balanceBefore);
        expect(await want.balanceOf(vault.address)).to.equal(balanceBefore);

        await strategy.connect(deployer).harvest();
        console.log(
            "estimatedTotalAssets",
            utils.formatUnits(await strategy.estimatedTotalAssets(), 6)
        );
        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseUnits("100", 6)
        );

        // await strategy.connect(deployer).harvest();

        mine(36000); // get more rewards
        console.log(
            "estimatedTotalAssets",
            utils.formatUnits(await strategy.estimatedTotalAssets(), 6)
        );
        await strategy.connect(deployer).harvest();
        // await strategy.connect(deployer).harvest();
        // await vault
        //     .connect(whale)
        //     ["withdraw(uint256,address,uint256)"](
        //         await vault.balanceOf(whale.address),
        //         whale.address,
        //         1000
        //     );
        // console.log(utils.formatUnits(await want.balanceOf(whale.address), 6));

        // expect(Number(await want.balanceOf(whale.address))).to.be.greaterThan(
        //     Number(balanceBefore)
        // );
    });
});
