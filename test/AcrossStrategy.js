const {
    loadFixture,
    mine,
    time,
    reset,
} = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { utils, BigNumber } = require("ethers");
const { parseEther } = require("ethers/lib/utils");
const { ethers } = require("hardhat");

const { getEnv } = require("../scripts/utils");

const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

const BASE_NODE = getEnv("ETH_NODE");
const BASE_FORK_BLOCK = getEnv("ETH_FORK_BLOCK");

// upgrades.silenceWarnings();

describe("AcrossStrategy", function () {
    const TOKENS = {
        WETH: { whale: "0x6B44ba0a126a2A1a8aa6cD1AdeeD002e141Bcd44" , address : "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"},
        ETH: {
            whale: "0xF977814e90dA44bFA03b6295A0616a897441aceC",
        },
    };


    async function deployContractAndSetVariables() {
        await reset(BASE_NODE, Number(BASE_FORK_BLOCK));
        const [deployer, governance, treasury, whale] = await ethers.getSigners();
        console.log(await ethers.provider.getBalance(deployer.address));
        const WETH_ADDRESS = TOKENS.WETH.address;
        const want = await ethers.getContractAt(IERC20_SOURCE, WETH_ADDRESS);
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
        await vault["setDepositLimit(uint256)"](ethers.utils.parseEther("10000"));

        const AcrossStrategy = await ethers.getContractFactory("AcrossStrategy");

        const strategy = await upgrades.deployProxy(
            AcrossStrategy,
            [vault.address, deployer.address],
            {
                initializer: "initialize",
                kind: "transparent",
                constructorArgs: [vault.address],
                unsafeAllow: ["constructor"],
            }
        );
        await strategy.deployed();

        await vault["addStrategy(address,uint256,uint256,uint256,uint256)"](
            strategy.address,
            10000,
            0,
            0,
            ethers.utils.parseEther("10000")
          );

        await dealTokensToAddress(whale.address, TOKENS.WETH, "1000");
        await want
            .connect(whale)
        ["approve(address,uint256)"](vault.address, ethers.constants.MaxUint256);

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
        const token = await ethers.getContractAt(IERC20_SOURCE, dealToken.address);

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
            .transfer(address, utils.parseUnits(amountUnscaled, dealToken.decimals));
    }

    it("should deploy strategy", async function () {
        const { vault, strategy } = await loadFixture(
            deployContractAndSetVariables
        );
        expect(await strategy.vault()).to.equal(vault.address);
        expect(await strategy.name()).to.equal("AcrossStrategy WETH");
    });

    // it("should get reasonable prices from oracle", async function () {
    //     const { strategy } = await loadFixture(deployContractAndSetVariables);
    //     const oneUnit = utils.parseEther("1");

    //     expect(Number(await strategy.LpToWant(oneUnit))).to.be.greaterThan(0);
    //     expect(Number(await strategy.AeroToWant(oneUnit))).to.be.greaterThan(0);
    // });

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
        await dealTokensToAddress(whale.address, TOKENS.WETH, "1000");
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
        await ethers.provider.send("evm_increaseTime", [50 * 24 * 60 * 60]);
        console.log(1);
        await strategy.connect(deployer).harvest();

        // Previous harvest indicated some profit and it was withdrawn to vault
        expect(Number(await want.balanceOf(vault.address))).to.be.greaterThan(0);
        // All profit from strategy was withdrawn to vault
        expect(Number(await want.balanceOf(strategy.address))).to.be.equal(0);
        await ethers.provider.send("evm_increaseTime", [50 * 24 * 60 * 60]);
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
        await ethers.provider.send("evm_increaseTime", [50 * 24 * 60 * 60]);

        console.log(await vault.balanceOf(whale.address));
        await vault
            .connect(whale)
        ["withdraw(uint256,address,uint256)"](
            await vault.balanceOf(whale.address),
            whale.address,
            1000
        );
        console.log("WITHDRAWED");
        expect((await want.balanceOf(whale.address))).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseUnits("100", 6)
        );

        const newWhaleBalance = await want.balanceOf(whale.address);
        console.log(newWhaleBalance);
        await vault.connect(whale)["deposit(uint256)"](newWhaleBalance);
        expect(Number(await want.balanceOf(whale.address))).to.be.equal(0);
        console.log("deposited");
        await ethers.provider.send("evm_increaseTime", [50 * 24 * 60 * 60]);

        await strategy.harvest();
        console.log("harvested");
        await dealTokensToAddress(strategy.address, TOKENS.WETH, "1000");
        await vault
            .connect(whale)
        ["withdraw(uint256,address,uint256)"](
            await vault.balanceOf(whale.address),
            whale.address,
            1000
        );
        expect((await want.balanceOf(whale.address))).to.be.closeTo(
            newWhaleBalance,
            ethers.utils.parseUnits("1", 18)
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
        await ethers.provider.send("evm_increaseTime", [50 * 24 * 60 * 60]);

        await strategy.connect(deployer).tend();

        await vault
            .connect(whale)
        ["withdraw(uint256,address,uint256)"](
            await vault.balanceOf(whale.address),
            whale.address,
            1000
        );
        expect((await want.balanceOf(whale.address))).to.be.closeTo(
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
        expect((await want.balanceOf(vault.address))).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseUnits("1", 18)
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

        const AcrossStrategy = await ethers.getContractFactory("AcrossStrategy");
        const newStrategy = await upgrades.deployProxy(
            AcrossStrategy,
            [vault.address, deployer.address],
            {
                initializer: "initialize",
                kind: "transparent",
                constructorArgs: [vault.address],
                unsafeAllow: ["constructor"],
            }
        );
        await newStrategy.deployed();

        const joeStaked = await strategy.balanceOfLPStaked();
        console.log("STAKED: ", joeStaked);
        await vault["migrateStrategy(address,address)"](
            strategy.address,
            newStrategy.address
        );
        console.log("ESTIMATED", await newStrategy.estimatedTotalAssets());
        expect(await strategy.estimatedTotalAssets()).to.be.equal(0);
        expect(await newStrategy.estimatedTotalAssets()).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseUnits("0.01", 18)
        );

        expect((await want.balanceOf(strategy.address))).to.be.equal(0);
        expect((await strategy.balanceOfLPStaked())).to.be.equal(0);
        expect((await newStrategy.balanceOfLPStaked())).to.be.equal(0);
        console.log(1);
        console.log(1);

        expect((await strategy.balanceOfWant())).to.be.equal(0);
        console.log(1);
        console.log(1);
        await newStrategy.harvest();

        expect((await strategy.balanceOfLPStaked())).to.be.equal(0);
        expect(BigNumber.from(await newStrategy.balanceOfLPStaked())).to.be.closeTo(
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
