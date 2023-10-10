const {
    loadFixture,
    mine,
    time,
    reset,
} = require("@nomicfoundation/hardhat-network-helpers");
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { expect } = require("chai");
const { utils, BigNumber } = require("ethers");
const { parseEther } = require("ethers/lib/utils");
const { ethers } = require("hardhat");

const { getEnv } = require("../scripts/utils");

const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

const BASE_NODE = getEnv("BASE_NODE");
const BASE_FORK_BLOCK = getEnv("BASE_FORK_BLOCK");

// upgrades.silenceWarnings();

describe("AeroStrategy", function () {
    const TOKENS = {
        USDC: {
            address: "0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA",
            whale: "0xc9d05a1c3c8e01dcb701d6185cdc21a5bb94becb",
            decimals: 6,
        },
        DAI: {
            address: "0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb",
            whale: "0x20f03e26968b179025f65c1f4afadfd3959c8d03",
            decimals: 18,
        },
        ETH: {
            whale: "0xdd9176eA3E7559D6B68b537eF555D3e89403f742"
        }
    };

    // const STABLE_JOE_STAKING = "0x43646A8e839B2f2766392C1BF8f60F6e587B6960";

    async function deployContractAndSetVariables() {
        await reset(BASE_NODE, Number(BASE_FORK_BLOCK));
        const [deployer, governance, treasury, whale] =
            await ethers.getSigners();
        const USDC_ADDRESS = TOKENS.USDC.address;
        const want = await ethers.getContractAt(IERC20_SOURCE, USDC_ADDRESS);
        const name = "lvDCI";
        const symbol = "vDeFi";
        const Vault = await ethers.getContractFactory("OnChainVault");
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

        const JOEStrategy = await ethers.getContractFactory("AeroStrategy");

        const strategy = await upgrades.deployProxy(
            JOEStrategy,
            [vault.address, deployer.address],
            {
                initializer: "initialize",
                kind: "transparent",
                constructorArgs: [vault.address],
                unsafeAllow: ["constructor"],
            }
        );
        await strategy.deployed();

        await vault["addStrategy(address,uint256,uint256)"](
            strategy.address,
            10000,
            0
        );

        await dealTokensToAddress(whale.address, TOKENS.USDC, "1000");
        await want
            .connect(whale)
        ["approve(address,uint256)"](
            vault.address,
            ethers.constants.MaxUint256
        );

        return {
            vault,
            deployer,
            want,
            whale,
            governance,
            treasury,
            strategy,
            want,
        };
    }

    async function dealTokensToAddress(
        address,
        dealToken,
        amountUnscaled = "100"
    ) {
        const token = await ethers.getContractAt(
            IERC20_SOURCE,
            dealToken.address
        );

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [dealToken.whale],
        });
        const tokenWhale = await ethers.getSigner(dealToken.whale);

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [TOKENS.ETH.whale],
        });
        const ethWhale = await ethers.getSigner(TOKENS.ETH.whale);

        await ethWhale.sendTransaction({
            to: tokenWhale.address,
            value: utils.parseEther("50"),
        });

        await token
            .connect(tokenWhale)
            .transfer(
                address,
                utils.parseUnits(amountUnscaled, dealToken.decimals)
            );
    }

    it("should deploy strategy", async function () {
        const { vault, strategy } = await loadFixture(
            deployContractAndSetVariables
        );
        expect(await strategy.vault()).to.equal(vault.address);
        expect(await strategy.name()).to.equal("Aerodrome USDbC/DAI Strategy");
    });

    it("should get reasonable prices from oracle", async function () {
        const { strategy } = await loadFixture(deployContractAndSetVariables);
        const oneUnit = utils.parseEther("1");

        expect(Number(await strategy.LpToWant(oneUnit))).to.be.greaterThan(0);
        expect(Number(await strategy.AeroToWant(oneUnit))).to.be.greaterThan(0);
    });

    it("should harvest with a profit", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        // Simulating whale depositing 1000 USDC into vault
        const balanceBefore = await want.balanceOf(whale.address);
        console.log(balanceBefore);
        await vault.connect(whale)["deposit(uint256)"](balanceBefore);
        expect(await want.balanceOf(vault.address)).to.equal(balanceBefore);
        await strategy.connect(deployer).harvest();
        console.log("HARVEST DONE");
        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseUnits("10", 6)
        );
        // We are dropping some USDC to staking contract to simulate profit from JOE staking
        await dealTokensToAddress(whale.address, TOKENS.USDC, "1000");
        console.log("PROBLEM");
        const deposit = await want.balanceOf(whale.address);
        // await ethers.provider.send('evm_increaseTime', [100 * 24 * 60 * 60])
        console.log(deposit);
        await vault.connect(whale)["deposit(uint256)"](deposit);
        console.log("ANOTHER HARVEST 1");
        let tx = await strategy.connect(deployer).harvest();
        console.log("ANOTHER HARVEST 1");
        await tx.wait();
        // expect(Number(await strategy.rewardss())).to.be.greaterThan(0);
        await ethers.provider.send('evm_increaseTime', [50 * 24 * 60 * 60])
        console.log(1);
        // await strategy.connect(deployer).harvest();

        // Previous harvest indicated some profit and it was withdrawn to vault
        expect(Number(await want.balanceOf(vault.address))).to.be.greaterThan(
            0
        );
        // All profit from strategy was withdrawn to vault
        expect(Number(await want.balanceOf(strategy.address))).to.be.equal(0);
        await ethers.provider.send('evm_increaseTime', [50 * 24 * 60 * 60])
        // Vault reinvesing its profit back to strategy
        await strategy.connect(deployer).harvest();
        console.log("GOOD JOB");
        expect(Number(await strategy.estimatedTotalAssets())).to.be.greaterThan(
            Number(balanceBefore)
        );
        console.log("Assets", Number(await strategy.estimatedTotalAssets()));
        // Mining blocks for unlocking all profit so whale can withdraw
        mine(36000);
        console.log(await vault.balanceOf(whale.address));
        await vault
            .connect(whale)
        ["withdraw(uint256,address,uint256)"](
            await vault.balanceOf(whale.address),
            whale.address,
            1000
        );
        console.log("WITHDRAW DONE");
        expect(Number(await want.balanceOf(whale.address))).to.be.greaterThan(
            Number(balanceBefore)
        );
    });

    it("should withdraw requested amount", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        const balanceBefore = await want.balanceOf(whale.address);
        console.log(balanceBefore);
        await vault.connect(whale)["deposit(uint256)"](balanceBefore);
        expect(await want.balanceOf(vault.address)).to.equal(balanceBefore);

        await strategy.connect(deployer).harvest();
        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseUnits("100", 6)
        );
        console.log("WITHDRAW");
        await ethers.provider.send('evm_increaseTime', [50 * 24 * 60 * 60])

        console.log(await vault.balanceOf(whale.address));
        await vault
            .connect(whale)
        ["withdraw(uint256,address,uint256)"](
            await vault.balanceOf(whale.address),
            whale.address,
            1000
        );
        console.log("WITHDRAWED");
        expect(Number(await want.balanceOf(whale.address))).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseUnits("100", 6)
        );

        const newWhaleBalance = await want.balanceOf(whale.address);
        console.log(newWhaleBalance)
        await vault.connect(whale)["deposit(uint256)"](newWhaleBalance);
        expect(Number(await want.balanceOf(whale.address))).to.be.equal(0);
        console.log("deposited");
        await ethers.provider.send('evm_increaseTime', [50 * 24 * 60 * 60])

        await strategy.harvest();
        console.log("harvested");
        await dealTokensToAddress(strategy.address, TOKENS.USDC, "1000");
        await vault
            .connect(whale)
        ["withdraw(uint256,address,uint256)"](
            (await vault.balanceOf(whale.address)),
            whale.address,
            1000
        );
        expect(Number(await want.balanceOf(whale.address))).to.be.closeTo(
            newWhaleBalance,
            ethers.utils.parseUnits("100", 6)
        );
    });

    it("should withdraw with loss", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        const balanceBefore = await want.balanceOf(whale.address);
        await vault.connect(whale)["deposit(uint256)"](balanceBefore);
        expect(await want.balanceOf(vault.address)).to.equal(balanceBefore);

        await strategy.connect(deployer).harvest();
        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseUnits("100", 6)
        );
        await ethers.provider.send('evm_increaseTime', [50 * 24 * 60 * 60])

        await strategy.connect(deployer).tend();

        await vault
            .connect(whale)
        ["withdraw(uint256,address,uint256)"](
            await vault.balanceOf(whale.address),
            whale.address,
            1000
        );
        expect(Number(await want.balanceOf(whale.address))).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseUnits("100", 6)
        );
    });

    it("should emergency exit", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        const balanceBefore = await want.balanceOf(whale.address);
        await vault.connect(whale)["deposit(uint256)"](balanceBefore);
        expect(await want.balanceOf(vault.address)).to.equal(balanceBefore);

        await strategy.connect(deployer).harvest();
        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseUnits("100", 6)
        );

        await strategy.setEmergencyExit();
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.equal(0);
        expect(Number(await want.balanceOf(vault.address))).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseUnits("100", 6)
        );
    });

    it("should migrate", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        const balanceBefore = await want.balanceOf(whale.address);
        await vault.connect(whale)["deposit(uint256)"](balanceBefore);
        expect(await want.balanceOf(vault.address)).to.equal(balanceBefore);

        await strategy.connect(deployer).harvest();
        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseUnits("100", 6)
        );

        const JOEStrategy = await ethers.getContractFactory("AeroStrategy");
        const newStrategy = await upgrades.deployProxy(
            JOEStrategy,
            [vault.address, deployer.address],
            {
                initializer: "initialize",
                kind: "transparent",
                constructorArgs: [vault.address],
                unsafeAllow: ["constructor"],
            }
        );
        await newStrategy.deployed();

        const joeStaked = await strategy.balanceOfStaked();

        await vault["migrateStrategy(address,address)"](
            strategy.address,
            newStrategy.address
        );

        expect(await strategy.estimatedTotalAssets()).to.be.equal(0);
        expect(await newStrategy.estimatedTotalAssets()).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseUnits("100", 6)
        );

        expect(Number(await want.balanceOf(strategy.address))).to.be.equal(0);
        expect(Number(await strategy.balanceOfStaked())).to.be.equal(0);
        expect(Number(await newStrategy.balanceOfStaked())).to.be.equal(0);
        console.log(1);

        expect(Number(await want.balanceOf(newStrategy.address))).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseUnits("100", 6)

        );
        console.log(1);

        expect(Number(await strategy.balanceOfWant())).to.be.equal(0);
        console.log(1);
        expect(Number(await newStrategy.balanceOfWant())).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseUnits("100", 6)
        );
        console.log(1);
        await newStrategy.harvest();

        expect(Number(await strategy.balanceOfStaked())).to.be.equal(0);
        expect(BigNumber.from(await newStrategy.balanceOfStaked())).to.be.closeTo(
            BigNumber.from(joeStaked),
            ethers.utils.parseUnits("1", 18)
        );
    });





    it("should withdraw on vault shutdown", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        const balanceBefore = await want.balanceOf(whale.address);
        await vault.connect(whale)["deposit(uint256)"](balanceBefore);
        expect(await want.balanceOf(vault.address)).to.equal(balanceBefore);

        await strategy.connect(deployer).harvest();
        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseUnits("100", 6)
        );

        await vault["setEmergencyShutdown(bool)"](true);
        mine(1);
        await vault
            .connect(whale)
        ["withdraw(uint256,address,uint256)"](
            await vault.balanceOf(whale.address),
            whale.address,
            1000
        );
        expect(await want.balanceOf(whale.address)).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseUnits("100", 6)
        );
    });

});
