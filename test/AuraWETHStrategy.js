const {
    loadFixture,
    mine,
    reset,
    time,
} = require("@nomicfoundation/hardhat-network-helpers");
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { expect } = require("chai");
const { utils, constants } = require("ethers");
const { ethers } = require("hardhat");

const { getEnv } = require("../scripts/utils");

const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

const AURA_WETH_REWARDS = "0x1204f5060be8b716f5a62b4df4ce32acd01a69f5";

const ETH_NODE_URL = getEnv("ETH_NODE");
const ETH_FORK_BLOCK = getEnv("ETH_FORK_BLOCK");

describe("AuraWETHStrategy", function () {
    const TOKENS = {
        USDC: {
            address: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            whale: "0xf646d9B7d20BABE204a89235774248BA18086dae",
            decimals: 6,
        },
        ETH: {
            address: ZERO_ADDRESS,
            whale: "0x00000000219ab540356cbb839cbe05303d7705fa",
            decimals: 18,
        },
        DAI: {
            address: "0x6b175474e89094c44da98b954eedeac495271d0f",
            whale: "0x60faae176336dab62e284fe19b885b095d29fb7f",
            decimals: 18,
        },
        AURA: {
            address: "0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF",
            whale: "0x39D787fdf7384597C7208644dBb6FDa1CcA4eBdf",
            decimals: 18,
        },
        BAL: {
            address: "0xba100000625a3754423978a60c9317c58a424e3D",
            whale: "0x740a4AEEfb44484853AA96aB12545FC0290805F3",
            decimals: 18,
        },
        WETH_AURA_BPT: {
            address: "0xCfCA23cA9CA720B6E98E3Eb9B6aa0fFC4a5C08B9",
            decimals: 18,
        },
    };

    async function deployContractAndSetVariables() {
        await reset(ETH_NODE_URL, Number(ETH_FORK_BLOCK));

        const [deployer, governance, treasury, whale] =
            await ethers.getSigners();
        const USDC_ADDRESS = TOKENS.USDC.address;
        const want = await ethers.getContractAt(IERC20_SOURCE, USDC_ADDRESS);

        const name = "dVault";
        const symbol = "vDeFi";
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

        const AuraWETHStrategy = await ethers.getContractFactory(
            "MockAuraWETHStrategy"
        );
        const strategy = await AuraWETHStrategy.deploy(vault.address);
        await strategy.deployed();

        await vault["addStrategy(address,uint256,uint256,uint256,uint256)"](
            strategy.address,
            10000,
            0,
            ethers.utils.parseEther("10000"),
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
        expect(await strategy.name()).to.equal("StrategyAuraWETH");
    });

    it("should get reasonable prices from oracle", async function () {
        const { strategy } = await loadFixture(deployContractAndSetVariables);
        const oneUnit = utils.parseEther("1");

        expect(Number(await strategy.auraToWant(oneUnit))).to.be.greaterThan(0);
        expect(Number(await strategy.balToWant(oneUnit))).to.be.greaterThan(0);
        expect(Number(await strategy.bptToWant(oneUnit))).to.be.greaterThan(0);
    });

    it("should harvest with a profit", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        // Simulating whale depositing 1000 USDC into vault
        const balanceBefore = await want.balanceOf(whale.address);
        await vault.connect(whale)["deposit(uint256)"](balanceBefore);
        expect(await want.balanceOf(vault.address)).to.equal(balanceBefore);

        await strategy.connect(deployer).harvest();
        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseUnits("100", 6)
        );

        // We are dropping some CRV to strategy to simulate profit from staking LP tokens in Aura
        await dealTokensToAddress(strategy.address, TOKENS.BAL, "1000");

        await strategy.connect(deployer).harvest();

        // Previous harvest indicated some profit and it was withdrawn to vault
        expect(Number(await want.balanceOf(vault.address))).to.be.greaterThan(
            0
        );

        // All profit from strategy was withdrawn to vault
        expect(Number(await want.balanceOf(strategy.address))).to.be.equal(0);

        // Vault reinvesing its profit back to strategy
        await strategy.connect(deployer).harvest();
        expect(Number(await strategy.estimatedTotalAssets())).to.be.greaterThan(
            Number(balanceBefore)
        );

        // Mining blocks for unlocking all profit so whale can withdraw
        mine(36000);

        await vault
            .connect(whale)
            ["withdraw(uint256,address,uint256)"](
                await vault.balanceOf(whale.address),
                whale.address,
                1000
            );
        expect(Number(await want.balanceOf(whale.address))).to.be.greaterThan(
            Number(balanceBefore)
        );
    });

    it("should withdraw requested amount", async function () {
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

        const newWhaleBalance = await want.balanceOf(whale.address);
        await vault.connect(whale)["deposit(uint256)"](newWhaleBalance);
        expect(Number(await want.balanceOf(whale.address))).to.be.equal(0);

        await strategy.harvest();

        await dealTokensToAddress(strategy.address, TOKENS.USDC, "1000");
        await vault
            .connect(whale)
            ["withdraw(uint256,address,uint256)"](
                await vault.balanceOf(whale.address),
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

        await strategy.connect(deployer).tend();

        await vault
            .connect(whale)
            ["withdraw(uint256,address,uint256)"](
                await vault.balanceOf(whale.address),
                whale.address,
                1000
            );
        expect(Number(await want.balanceOf(whale.address))).to.be.lessThan(
            Number(balanceBefore)
        );
        expect(Number(await want.balanceOf(whale.address))).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseUnits("100", 6)
        );
    });

    it("should not withdraw with loss", async function () {
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

        await strategy.connect(deployer).tend();

        await expect(
            vault
                .connect(whale)
                ["withdraw(uint256,address,uint256)"](
                    await vault.balanceOf(whale.address),
                    whale.address,
                    0
                )
        ).to.be.reverted;
    });

    it("should withdraw without loss", async function () {
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

        // Dropping some USDC to strategy for accodomating loss
        await dealTokensToAddress(strategy.address, TOKENS.USDC, "500");
        // Force to sell all staked Curve LP to fulfill withdraw request for 100%
        await strategy.overrideWantToBpt(await strategy.balanceOfAuraBpt());

        await vault
            .connect(whale)
            ["withdraw(uint256,address,uint256)"](
                await vault.balanceOf(whale.address),
                whale.address,
                0
            );
        expect(Number(await want.balanceOf(whale.address))).to.be.equal(
            balanceBefore
        );
    });

    it("should report loss without withdrawing funds", async function () {
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

        const auraLPStakedBefore = await strategy.balanceOfAuraBpt();

        expect(Number(await strategy.estimatedTotalAssets())).to.be.greaterThan(
            0
        );
        await strategy.overrideEstimatedTotalAssets(0);
        expect(Number(await strategy.estimatedTotalAssets())).to.be.equal(0);
        await strategy.connect(deployer).harvest();

        const auraLPStakedAfter = await strategy.balanceOfAuraBpt();
        expect(Number(auraLPStakedBefore)).to.be.not.greaterThan(
            Number(auraLPStakedAfter)
        );
    });

    it("should change slippage", async function () {
        const { strategy, whale, deployer } = await loadFixture(
            deployContractAndSetVariables
        );

        await expect(strategy.connect(whale).setSlippage(0)).to.be.reverted;
        await expect(strategy.connect(deployer).setSlippage(10_000)).to.be
            .reverted;
        await strategy.connect(deployer).setSlippage(100);
        expect(await strategy.slippage()).to.equal(100);
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

    it("should sweep", async function () {
        const { vault, strategy, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        await expect(
            strategy.connect(deployer)["sweep(address)"](want.address)
        ).to.be.revertedWith("!want");
        await expect(
            strategy.connect(deployer)["sweep(address)"](vault.address)
        ).to.be.revertedWith("!shares");
        await expect(
            strategy.connect(deployer)["sweep(address)"](TOKENS.AURA.address)
        ).to.be.revertedWith("!protected");
        await expect(
            strategy.connect(deployer)["sweep(address)"](TOKENS.BAL.address)
        ).to.be.revertedWith("!protected");
        await expect(
            strategy
                .connect(deployer)
                ["sweep(address)"](TOKENS.WETH_AURA_BPT.address)
        ).to.be.revertedWith("!protected");

        const daiToken = await hre.ethers.getContractAt(
            IERC20_SOURCE,
            TOKENS.DAI.address
        );
        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [TOKENS.DAI.whale],
        });
        const daiWhale = await ethers.getSigner(TOKENS.DAI.whale);

        await daiToken
            .connect(daiWhale)
            .transfer(strategy.address, ethers.utils.parseEther("10"));
        expect(TOKENS.DAI.address).not.to.be.equal(await strategy.want());
        await expect(() =>
            strategy.connect(deployer)["sweep(address)"](daiToken.address)
        ).to.changeTokenBalances(
            daiToken,
            [strategy, deployer],
            [ethers.utils.parseEther("-10"), ethers.utils.parseEther("10")]
        );
    });

    it("should change debt", async function () {
        const { vault, whale, strategy, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        const balanceBefore = await want.balanceOf(whale.address);
        await vault.connect(whale)["deposit(uint256)"](balanceBefore);
        expect(await want.balanceOf(vault.address)).to.equal(balanceBefore);

        await vault
            .connect(deployer)
            ["updateStrategyDebtRatio(address,uint256)"](
                strategy.address,
                5000
            );
        mine(1);
        await strategy.harvest();
        expect(Number(await strategy.estimatedTotalAssets())).to.be.closeTo(
            ethers.utils.parseUnits("500", 6),
            ethers.utils.parseUnits("50", 6)
        );

        await vault
            .connect(deployer)
            ["updateStrategyDebtRatio(address,uint256)"](
                strategy.address,
                10000
            );
        mine(1);
        await strategy.harvest();
        expect(Number(await strategy.estimatedTotalAssets())).to.be.closeTo(
            ethers.utils.parseUnits("1000", 6),
            ethers.utils.parseUnits("100", 6)
        );

        await vault
            .connect(deployer)
            ["updateStrategyDebtRatio(address,uint256)"](
                strategy.address,
                5000
            );
        mine(1);
        await strategy.harvest();
        expect(Number(await strategy.estimatedTotalAssets())).to.be.closeTo(
            ethers.utils.parseUnits("500", 6),
            ethers.utils.parseUnits("50", 6)
        );
    });

    it("should trigger", async function () {
        const { vault, whale, strategy, want } = await loadFixture(
            deployContractAndSetVariables
        );

        const balanceBefore = await want.balanceOf(whale.address);
        await vault.connect(whale)["deposit(uint256)"](balanceBefore);
        expect(await want.balanceOf(vault.address)).to.equal(balanceBefore);

        await time.increase(await strategy.maxReportDelay());

        expect(await strategy.harvestTrigger(0)).to.be.true;
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

        const AuraWETHStrategy = await ethers.getContractFactory(
            "AuraWETHStrategy"
        );
        const newStrategy = await AuraWETHStrategy.deploy(vault.address);
        await newStrategy.deployed();

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
        expect(Number(await strategy.balanceOfAuraBpt())).to.be.equal(0);
        expect(Number(await newStrategy.balanceOfAuraBpt())).to.be.equal(0);
        expect(
            Number(await newStrategy.balanceOfUnstakedBpt())
        ).to.be.greaterThan(0);
        expect(Number(await strategy.balanceOfUnstakedBpt())).to.be.equal(0);

        await newStrategy.harvest();

        expect(Number(await strategy.balanceOfAuraBpt())).to.be.equal(0);
        expect(Number(await newStrategy.balanceOfAuraBpt())).to.be.greaterThan(
            0
        );
    });

    it("should revoke from vault", async function () {
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

        await vault["revokeStrategy(address)"](strategy.address);
        await strategy.harvest();
        expect(await strategy.estimatedTotalAssets()).to.be.equal(0);
        expect(await want.balanceOf(vault.address)).to.be.closeTo(
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

        await strategy["setEmergencyExit()"]();
        await strategy.harvest();
        expect(await want.balanceOf(vault.address)).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseUnits("100", 6)
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

    it("should accrue some rewards after some time", async function () {
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

        await mine(300, { interval: 20 });

        expect(Number(await strategy.balRewards())).to.be.greaterThan(0);
        expect(
            Number(await strategy.auraRewards(await strategy.balRewards()))
        ).to.be.greaterThan(0);
    });

    it("should change AURA PID and AURA rewards", async function () {
        const { strategy, whale, deployer } = await loadFixture(
            deployContractAndSetVariables
        );

        expect(await strategy.AURA_PID()).to.be.equal(100);
        await expect(strategy.connect(whale)["setAuraPid(uint256)"](200)).to.be
            .reverted;
        await strategy.connect(deployer)["setAuraPid(uint256)"](200);
        expect(await strategy.AURA_PID()).to.be.equal(200);

        expect(
            (await strategy.AURA_WETH_REWARDS()).toLocaleLowerCase()
        ).to.be.equal(AURA_WETH_REWARDS.toLocaleLowerCase());
        await expect(
            strategy
                .connect(whale)
                ["setAuraWethRewards(address)"](constants.AddressZero)
        ).to.be.reverted;
        await strategy
            .connect(deployer)
            ["setAuraWethRewards(address)"](constants.AddressZero);
        expect(await strategy.AURA_WETH_REWARDS()).to.be.equal(
            constants.AddressZero
        );
    });
});
