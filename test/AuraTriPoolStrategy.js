const {
    loadFixture,
    mine,
    reset,
} = require("@nomicfoundation/hardhat-network-helpers");
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { expect } = require("chai");
const { utils, constants } = require("ethers");
const { ethers } = require("hardhat");

const { getEnv } = require("../scripts/utils");

const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

const ETH_NODE_URL = getEnv("ETH_NODE");
const ETH_FORK_BLOCK = getEnv("ETH_FORK_BLOCK");

upgrades.silenceWarnings();

const BAL_LP = "0x42ED016F826165C2e5976fe5bC3df540C5aD0Af7";
const AURA_STAKED_LP = "0x032B676d5D55e8ECbAe88ebEE0AA10fB5f72F6CB";

describe("AuraTriPoolStrategy", function () {
    const TOKENS = {
        USDC: {
            address: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            whale: "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503",
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
        WETH: {
            address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
            whale: "0x8EB8a3b98659Cce290402893d0123abb75E3ab28",
            decimals: 18,
        },
    };

    async function deployContractAndSetVariables() {
        await reset(ETH_NODE_URL, Number(ETH_FORK_BLOCK));

        const [deployer, governance, treasury, whale] =
            await ethers.getSigners();
        const want = await ethers.getContractAt(
            IERC20_SOURCE,
            TOKENS.WETH.address
        );

        const name = "ETH Vault";
        const symbol = "lvETH";
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

        const AuraTriPoolStrategy = await ethers.getContractFactory(
            "AuraTriPoolStrategy"
        );
        const strategy = await upgrades.deployProxy(
            AuraTriPoolStrategy,
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

        await dealTokensToAddress(whale.address, TOKENS.WETH, "10");
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
        expect(await strategy.name()).to.equal("StrategyAuraTriPool");
    });

    it("should get reasonable prices from oracle", async function () {
        const { strategy } = await loadFixture(deployContractAndSetVariables);
        const oneUnit = utils.parseEther("1");

        expect(Number(await strategy.auraToWant(oneUnit))).to.be.greaterThan(0);
        expect(Number(await strategy.balToWant(oneUnit))).to.be.greaterThan(0);
        expect(Number(await strategy.bptToWant(oneUnit))).to.be.greaterThan(0);
        expect(Number(await strategy.ethToWant(oneUnit))).to.be.greaterThan(0);
    });

    it("should harvest with a profit", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        // Simulating whale depositing 10 ETH into vault
        const balanceBefore = await want.balanceOf(whale.address);
        await vault.connect(whale)["deposit(uint256)"](balanceBefore);
        expect(await want.balanceOf(vault.address)).to.equal(balanceBefore);

        await strategy.connect(deployer).harvest();
        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseEther("0.2")
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
            ethers.utils.parseEther("0.2")
        );

        await vault
            .connect(whale)
        ["withdraw(uint256,address,uint256)"](
            await vault.balanceOf(whale.address),
            whale.address,
            1000
        );
        expect(await want.balanceOf(whale.address)).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseEther("0.2")
        );

        const newWhaleBalance = await want.balanceOf(whale.address);
        await vault.connect(whale)["deposit(uint256)"](newWhaleBalance);
        expect(await want.balanceOf(whale.address)).to.be.equal(0);

        await strategy.harvest();

        await dealTokensToAddress(strategy.address, TOKENS.WETH, "1");
        await vault
            .connect(whale)
        ["withdraw(uint256,address,uint256)"](
            await vault.balanceOf(whale.address),
            whale.address,
            1000
        );
        expect(await want.balanceOf(whale.address)).to.be.closeTo(
            newWhaleBalance,
            ethers.utils.parseEther("0.2")
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
            ethers.utils.parseEther("0.2")
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
        expect(await want.balanceOf(whale.address)).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseEther("0.2")
        );
    });

    it("should set slippages", async function () {
        const { strategy, deployer } = await loadFixture(
            deployContractAndSetVariables
        );

        await strategy.connect(deployer)["setSlippage(uint256)"](9999);
        expect(await strategy.slippage()).to.be.equal(9999);

        await strategy.connect(deployer)["setRewardsSlippage(uint256)"](9999);
        expect(await strategy.rewardsSlippage()).to.be.equal(9999);
    });

    it("should fail harvest with small rewards slippage", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        await strategy.connect(deployer)["setRewardsSlippage(uint256)"](9999);
        await want
            .connect(whale)
            .approve(vault.address, ethers.utils.parseEther("10"));
        await vault
            .connect(whale)
        ["deposit(uint256)"](ethers.utils.parseEther("10"));
        expect(await want.balanceOf(vault.address)).to.equal(
            ethers.utils.parseEther("10")
        );

        await strategy.connect(deployer).harvest();
        mine(38000); // get more rewards

        await expect(strategy.connect(deployer).harvest()).to.be.reverted;

        await strategy.connect(deployer)["setRewardsSlippage(uint256)"](9000);
        await strategy.connect(deployer).harvest();
        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("10"),
            ethers.utils.parseEther("0.2")
        );
    });

    it("should withdraw requested amount (more ETH)", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        await dealTokensToAddress(whale.address, TOKENS.WETH, "90");
        const balanceBefore = await want.balanceOf(whale.address);

        await want
            .connect(whale)
            .approve(vault.address, ethers.utils.parseEther("100"));
        await vault
            .connect(whale)
        ["deposit(uint256)"](ethers.utils.parseEther("100"));
        expect(await want.balanceOf(vault.address)).to.equal(
            ethers.utils.parseEther("100")
        );

        await strategy.connect(deployer).harvest();
        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("100"),
            ethers.utils.parseEther("2.5")
        );

        await strategy.connect(deployer).harvest();
        await vault.connect(whale)["withdraw(uint256,address,uint256)"](
            ethers.utils.parseEther("100"),
            whale.address,
            1000 // 10% acceptable loss
        );

        expect(await want.balanceOf(whale.address)).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseEther("2.5")
        );
    });

    it("should not withdraw with loss", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        await dealTokensToAddress(whale.address, TOKENS.WETH, "90");
        await want
            .connect(whale)
            .approve(vault.address, ethers.utils.parseEther("100"));
        await vault
            .connect(whale)
        ["deposit(uint256)"](ethers.utils.parseEther("100"));

        const balanceBefore = await want.balanceOf(whale.address);

        expect(await want.balanceOf(vault.address)).to.equal(
            ethers.utils.parseEther("100")
        );

        await strategy.connect(deployer).harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("100"),
            ethers.utils.parseEther("2")
        );

        await strategy.connect(deployer).tend();

        await expect(
            vault.connect(whale)["withdraw(uint256,address,uint256)"](
                ethers.utils.parseEther("100"),
                whale.address,
                0 // 0% acceptable loss
            )
        ).to.be.reverted;

        expect(await want.balanceOf(whale.address)).to.equal(balanceBefore);
    });

    it("should sweep", async function () {
        const { vault, deployer, strategy, whale, want } = await loadFixture(
            deployContractAndSetVariables
        );

        const oneEther = ethers.utils.parseEther("1");
        await want.connect(whale).transfer(strategy.address, oneEther);

        expect(want.address).to.equal(await strategy.want());
        expect(Number(await want.balanceOf(strategy.address))).to.greaterThan(
            Number(0)
        );

        await expect(
            strategy.connect(deployer)["sweep(address)"](want.address)
        ).to.be.revertedWith("!want");
        await expect(
            strategy.connect(deployer)["sweep(address)"](vault.address)
        ).to.be.revertedWith("!shares");
        await expect(
            strategy.connect(deployer)["sweep(address)"](TOKENS.BAL.address)
        ).to.be.revertedWith("!protected");
        await expect(
            strategy.connect(deployer)["sweep(address)"](TOKENS.AURA.address)
        ).to.be.revertedWith("!protected");
        await expect(
            strategy.connect(deployer)["sweep(address)"](BAL_LP)
        ).to.be.revertedWith("!protected");

        const daiToken = await hre.ethers.getContractAt(
            IERC20_SOURCE,
            TOKENS.DAI.address
        );
        const daiWhaleAddress = "0x60faae176336dab62e284fe19b885b095d29fb7f";
        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [daiWhaleAddress],
        });
        const daiWhale = await ethers.getSigner(TOKENS.DAI.whale);

        await daiToken
            .connect(daiWhale)
            .transfer(strategy.address, ethers.utils.parseEther("10"));
        expect(daiToken.address).not.to.be.equal(await strategy.want());
        await expect(() =>
            strategy.connect(deployer)["sweep(address)"](daiToken.address)
        ).to.changeTokenBalances(
            daiToken,
            [strategy, deployer],
            [ethers.utils.parseEther("-10"), ethers.utils.parseEther("10")]
        );
    });

    it("should change debt", async function () {
        const { vault, strategy, deployer, whale, want } = await loadFixture(
            deployContractAndSetVariables
        );

        const oneEther = ethers.utils.parseEther("1");
        await want.connect(whale).approve(vault.address, oneEther);
        await vault.connect(whale)["deposit(uint256)"](oneEther);
        await vault
            .connect(deployer)
        ["updateStrategyDebtRatio(address,uint256)"](
            strategy.address,
            5000
        );
        mine(1);
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("0.5"),
            ethers.utils.parseEther("0.025")
        );

        await vault
            .connect(deployer)
        ["updateStrategyDebtRatio(address,uint256)"](
            strategy.address,
            10000
        );
        mine(1000);
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("1"),
            ethers.utils.parseEther("0.025")
        );

        await vault
            .connect(deployer)
        ["updateStrategyDebtRatio(address,uint256)"](
            strategy.address,
            5000
        );
        mine(1000);
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("0.5"),
            ethers.utils.parseEther("0.025")
        );
    });

    it("should trigger", async function () {
        const { vault, strategy, deployer, whale, want } = await loadFixture(
            deployContractAndSetVariables
        );

        const oneEther = ethers.utils.parseEther("1");
        await want.connect(whale).approve(vault.address, oneEther);
        await vault.connect(whale)["deposit(uint256)"](oneEther);
        await vault
            .connect(deployer)
        ["updateStrategyDebtRatio(address,uint256)"](
            strategy.address,
            5000
        );
        mine(1);
        await strategy.harvest();

        await strategy.harvestTrigger(0);
        await strategy.tendTrigger(0);
    });

    it("should migrate", async function () {
        const { vault, strategy, deployer, whale, want } = await loadFixture(
            deployContractAndSetVariables
        );

        const oneEther = ethers.utils.parseEther("1");
        await want.connect(whale).approve(vault.address, oneEther);
        await vault.connect(whale)["deposit(uint256)"](oneEther);

        await strategy.harvest();
        mine(1000);

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("1"),
            ethers.utils.parseEther("0.025")
        );

        const AuraTriPoolStrategy = await ethers.getContractFactory(
            "AuraTriPoolStrategy"
        );
        const newStrategy = await upgrades.deployProxy(
            AuraTriPoolStrategy,
            [vault.address, deployer.address],
            {
                initializer: "initialize",
                kind: "transparent",
                constructorArgs: [vault.address],
                unsafeAllow: ["constructor"],
            }
        );
        await newStrategy.deployed();

        const auraToken = await hre.ethers.getContractAt(
            IERC20_SOURCE,
            TOKENS.AURA.address
        );
        const balToken = await hre.ethers.getContractAt(
            IERC20_SOURCE,
            TOKENS.BAL.address
        );
        const bptTokens = await hre.ethers.getContractAt(IERC20_SOURCE, BAL_LP);
        const auraBptTokens = await hre.ethers.getContractAt(
            IERC20_SOURCE,
            AURA_STAKED_LP
        );

        await vault["migrateStrategy(address,address)"](
            strategy.address,
            newStrategy.address
        );

        expect(await strategy.estimatedTotalAssets()).to.be.equal(0);
        expect(await newStrategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("1"),
            ethers.utils.parseEther("0.025")
        );
        expect(
            Number(await auraToken.balanceOf(newStrategy.address))
        ).to.be.greaterThan(0);
        expect(
            Number(await balToken.balanceOf(newStrategy.address))
        ).to.be.greaterThan(0);
        expect(
            Number(await bptTokens.balanceOf(newStrategy.address))
        ).to.be.greaterThan(0);
        expect(
            Number(await auraBptTokens.balanceOf(newStrategy.address))
        ).to.be.equal(0);

        await newStrategy.harvest();

        expect(
            Number(await auraToken.balanceOf(newStrategy.address))
        ).to.be.equal(0);
        expect(
            Number(await balToken.balanceOf(newStrategy.address))
        ).to.be.equal(0);
        expect(
            Number(await bptTokens.balanceOf(newStrategy.address))
        ).to.be.equal(0);
        expect(
            Number(await auraBptTokens.balanceOf(newStrategy.address))
        ).to.be.greaterThan(0);

        expect(await newStrategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("1"),
            ethers.utils.parseEther("0.025")
        );
    });

    it("should revoke from vault", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        await dealTokensToAddress(whale.address, TOKENS.WETH, "90");

        await want
            .connect(whale)
            .approve(vault.address, ethers.utils.parseEther("100"));
        await vault
            .connect(whale)
        ["deposit(uint256)"](ethers.utils.parseEther("100"));
        mine(1);
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("100"),
            ethers.utils.parseEther("2")
        );

        await vault["revokeStrategy(address)"](strategy.address);
        mine(1);
        await strategy.harvest();
        expect(await want.balanceOf(vault.address)).to.be.closeTo(
            ethers.utils.parseEther("100"),
            ethers.utils.parseEther("2")
        );
    });

    it("should emergency exit", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        await dealTokensToAddress(whale.address, TOKENS.WETH, "90");

        await want
            .connect(whale)
            .approve(vault.address, ethers.utils.parseEther("100"));
        await vault
            .connect(whale)
        ["deposit(uint256)"](ethers.utils.parseEther("100"));
        mine(1);
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("100"),
            ethers.utils.parseEther("2")
        );

        await strategy["setEmergencyExit()"]();
        mine(1);
        await strategy.harvest();
        expect(await want.balanceOf(vault.address)).to.be.closeTo(
            ethers.utils.parseEther("100"),
            ethers.utils.parseEther("2")
        );
    });

    it("should withdraw on vault shutdown", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        await dealTokensToAddress(whale.address, TOKENS.WETH, "90");

        await want
            .connect(whale)
            .approve(vault.address, ethers.utils.parseEther("100"));
        await vault
            .connect(whale)
        ["deposit(uint256)"](ethers.utils.parseEther("100"));
        expect(await want.balanceOf(vault.address)).to.equal(
            ethers.utils.parseEther("100")
        );

        if ((await want.balanceOf(whale.address)) > 0) {
            want.connect(whale).transfer(
                ZERO_ADDRESS,
                await want.balanceOf(whale.address)
            );
        }
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("100"),
            ethers.utils.parseEther("2")
        );

        await vault["setEmergencyShutdown(bool)"](true);
        await vault.connect(whale)["withdraw(uint256,address,uint256)"](
            ethers.utils.parseEther("100"),
            whale.address,
            1000 // 10% acceptable loss
        );
        expect(await want.balanceOf(whale.address)).to.be.closeTo(
            ethers.utils.parseEther("100"),
            ethers.utils.parseEther("2")
        );
    });

    it("should not liquidate when enough want", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        await want
            .connect(whale)
            .approve(vault.address, ethers.utils.parseEther("1"));
        await vault
            .connect(whale)
        ["deposit(uint256)"](ethers.utils.parseEther("1"));

        await strategy.connect(deployer).harvest();

        want.connect(whale).transfer(
            strategy.address,
            ethers.utils.parseEther("8")
        );

        await expect(vault.connect(whale)["withdraw()"]()).not.to.be.reverted;
    });

    it("sell 0 AURA", async function () {
        const { strategy } = await loadFixture(deployContractAndSetVariables);
        await dealTokensToAddress(strategy.address, TOKENS.BAL, "100");
        await strategy.tend();
        expect(Number(await strategy.estimatedTotalAssets())).to.be.greaterThan(
            0
        );

        await dealTokensToAddress(strategy.address, TOKENS.AURA, "100");
        await strategy.tend();
        expect(Number(await strategy.estimatedTotalAssets())).to.be.greaterThan(
            0
        );
    });

    it("should change AURA PID and AURA rewards", async function () {
        const { strategy, whale, deployer } = await loadFixture(
            deployContractAndSetVariables
        );

        expect(await strategy.AURA_PID()).to.be.equal(139);
        await expect(strategy.connect(whale)["setAuraPid(uint256)"](200)).to.be
            .reverted;
        await strategy.connect(deployer)["setAuraPid(uint256)"](200);
        expect(await strategy.AURA_PID()).to.be.equal(200);

        expect(
            (await strategy.AURA_TRIPOOL_REWARDS()).toLocaleLowerCase()
        ).to.be.equal(AURA_STAKED_LP.toLocaleLowerCase());
        await expect(
            strategy
                .connect(whale)
            ["setAuraTriPoolRewards(address)"](constants.AddressZero)
        ).to.be.reverted;
        await strategy
            .connect(deployer)
        ["setAuraTriPoolRewards(address)"](constants.AddressZero);
        expect(await strategy.AURA_TRIPOOL_REWARDS()).to.be.equal(
            constants.AddressZero
        );
    });
});
