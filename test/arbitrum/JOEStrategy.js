const {
    loadFixture,
    mine,
    time,
    reset,
} = require("@nomicfoundation/hardhat-network-helpers");
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { expect } = require("chai");
const { utils } = require("ethers");
const { parseEther } = require("ethers/lib/utils");
const { ethers } = require("hardhat");

const { getEnv } = require("../../scripts/utils");

const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

const ARBITRUM_NODE_URL = getEnv("ARBITRUM_NODE");
const ARBITRUM_FORK_BLOCK = getEnv("ARBITRUM_FORK_BLOCK");

describe.only("JOEStrategy", function () {
    const TOKENS = {
        USDC: {
            address: "0xff970a61a04b1ca14834a43f5de4533ebddb5cc8",
            whale: "0x62383739d68dd0f844103db8dfb05a7eded5bbe6",
            decimals: 6,
        },
        ETH: {
            address: ZERO_ADDRESS,
            whale: "0xf977814e90da44bfa03b6295a0616a897441acec",
            decimals: 18,
        },
        DAI: {
            address: "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1",
            whale: "0x2ac5f9a2a69700090755d5b3caa8c4cba0b748f9",
            decimals: 18,
        },
        JOE: {
            address: "0x371c7ec6D8039ff7933a2AA28EB827Ffe1F52f07",
            whale: "0x1446e040b1ef8253b48fc09930576d9b67142804",
            decimals: 18,
        },
    };

    const STABLE_JOE_STAKING = "0x43646A8e839B2f2766392C1BF8f60F6e587B6960";

    async function deployContractAndSetVariables() {
        await reset(ARBITRUM_NODE_URL, Number(ARBITRUM_FORK_BLOCK));

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

        const JOEStrategy = await ethers.getContractFactory("MockJOEStrategy");
        const strategy = await JOEStrategy.deploy(vault.address);
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
        expect(await strategy.name()).to.equal("StrategyJOE");
    });

    it("should get reasonable prices from oracle", async function () {
        const { strategy } = await loadFixture(deployContractAndSetVariables);
        const oneUnit = utils.parseEther("1");

        expect(Number(await strategy.ethToWant(oneUnit))).to.be.greaterThan(0);
        expect(Number(await strategy.joeToWant(oneUnit))).to.be.greaterThan(0);
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

        // // We are dropping some USDC to staking contract to simulate profit from JOE
        await dealTokensToAddress(STABLE_JOE_STAKING, TOKENS.USDC, "1000000");
        expect(Number(await strategy.balanceOfRewards())).to.be.greaterThan(0);

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
        // Force to sell all staked JOE to fulfill withdraw request for 100%
        await strategy.overrideWantToJoe(await strategy.balanceOfStakedJoe());

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

    it("should withdraw rewards only", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        const balanceBefore = utils.parseUnits("10", 6);
        await dealTokensToAddress(deployer.address, TOKENS.USDC, "10");
        await want
            .connect(deployer)
            ["approve(address,uint256)"](
                vault.address,
                ethers.constants.MaxUint256
            );
        await vault.connect(deployer)["deposit(uint256)"](balanceBefore);

        await vault
            .connect(whale)
            ["deposit(uint256)"](utils.parseUnits("1000", 6));

        await strategy.connect(deployer).harvest();
        await dealTokensToAddress(STABLE_JOE_STAKING, TOKENS.USDC, "1000000");

        await vault
            .connect(deployer)
            ["withdraw(uint256,address,uint256)"](
                await vault.balanceOf(deployer.address),
                deployer.address,
                0
            );
        expect(Number(await want.balanceOf(deployer.address))).to.be.equal(
            Number(balanceBefore)
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

        const joeStakedBefore = await strategy.balanceOfStakedJoe();

        expect(Number(await strategy.estimatedTotalAssets())).to.be.greaterThan(
            0
        );
        await strategy.overrideEstimatedTotalAssets(0);
        expect(Number(await strategy.estimatedTotalAssets())).to.be.equal(0);
        await strategy.connect(deployer).harvest();

        const joeStakedAfter = await strategy.balanceOfStakedJoe();
        expect(Number(joeStakedBefore)).to.be.not.greaterThan(
            Number(joeStakedAfter)
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
            strategy.connect(deployer)["sweep(address)"](TOKENS.JOE.address)
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

        const JOEStrategy = await ethers.getContractFactory("JOEStrategy");
        const newStrategy = await JOEStrategy.deploy(vault.address);
        await newStrategy.deployed();

        const joeStaked = await strategy.balanceOfStakedJoe();

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
        expect(Number(await strategy.balanceOfStakedJoe())).to.be.equal(0);
        expect(Number(await newStrategy.balanceOfStakedJoe())).to.be.equal(0);
        expect(Number(await want.balanceOf(newStrategy.address))).to.be.equal(
            0
        );
        expect(Number(await strategy.balanceOfUnstakedJoe())).to.be.equal(0);
        expect(Number(await newStrategy.balanceOfUnstakedJoe())).to.be.equal(
            Number(joeStaked)
        );

        await newStrategy.harvest();

        expect(Number(await strategy.balanceOfStakedJoe())).to.be.equal(0);
        expect(Number(await newStrategy.balanceOfStakedJoe())).to.be.equal(
            Number(joeStaked)
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

    it("should change reward token", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        await expect(strategy.setRewardToken(TOKENS.DAI.address)).to.be
            .reverted;

        // We are setting reward token to JOE which is not yet supported by the vesting contract.
        // This is unlikely to happen but we need to test it.
        await strategy.setRewardToken(TOKENS.JOE.address);
        expect(await strategy.JOE_REWARD_TOKEN()).to.equal(TOKENS.JOE.address);

        await expect(strategy.balanceOfRewards()).to.be.revertedWith(
            "StableJoeStaking: wrong reward token"
        );
    });
});
