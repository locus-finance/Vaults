const {
    loadFixture,
    mine,
    reset,
    time,
} = require("@nomicfoundation/hardhat-network-helpers");
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { expect } = require("chai");
const { utils } = require("ethers");
const { ethers } = require("hardhat");

const { getEnv } = require("../scripts/utils");

const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

const ETH_NODE_URL = getEnv("ETH_NODE");
const ETH_FORK_BLOCK = getEnv("ETH_FORK_BLOCK");

upgrades.silenceWarnings();

describe("FXSStrategy", function () {
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
        CRV: {
            address: "0xD533a949740bb3306d119CC777fa900bA034cd52",
            whale: "0xF977814e90dA44bFA03b6295A0616a897441aceC",
            decimals: 18,
        },
        CVX: {
            address: "0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B",
            whale: "0xcba0074a77A3aD623A80492Bb1D8d932C62a8bab",
            decimals: 18,
        },
        FXS: {
            address: "0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0",
            whale: "0xd53E50c63B0D549f142A2dCfc454501aaA5B7f3F",
            decimals: 18,
        },
        CURVE_FXS_LP: {
            address: "0x6a9014FB802dCC5efE3b97Fd40aAa632585636D0",
            whale: "0xdc88d12721F9cA1404e9e6E6389aE0AbDd54fc6C",
            decimals: 18,
        },
    };

    async function deployContractAndSetVariables() {
        await reset(ETH_NODE_URL, Number(ETH_FORK_BLOCK));

        const [deployer, governance, treasury, whale] =
            await ethers.getSigners();
        const USDC_ADDRESS = TOKENS.USDC.address;
        const want = await ethers.getContractAt(IERC20_SOURCE, USDC_ADDRESS);

        const name = "lvDCI";
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

        const FXSStrategy = await ethers.getContractFactory("MockFXSStrategy");
        const strategy = await upgrades.deployProxy(
            FXSStrategy,
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
        expect(await strategy.name()).to.equal("StrategyFXS");
    });

    it("should get reasonable prices from oracle", async function () {
        const { strategy } = await loadFixture(deployContractAndSetVariables);
        const oneUnit = utils.parseEther("1");

        expect(Number(await strategy.ethToWant(oneUnit))).to.be.greaterThan(0);
        expect(Number(await strategy.crvToWant(oneUnit))).to.be.greaterThan(0);
        expect(Number(await strategy.cvxToWant(oneUnit))).to.be.greaterThan(0);
        expect(Number(await strategy.curveLPToWant(oneUnit))).to.be.greaterThan(
            0
        );
        expect(Number(await strategy.fxsToWant(oneUnit))).to.be.greaterThan(0);
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

        // We are dropping some CRV to strategy to simulate profit from staking in Convex
        await dealTokensToAddress(strategy.address, TOKENS.CRV, "1000");

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
        mine(36000, { interval: 20 });

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
        await strategy.overrideWantToCurveLP(
            await strategy.balanceOfCurveLPStaked()
        );

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

        const curveLPStakedBefore = await strategy.balanceOfCurveLPStaked();

        expect(Number(await strategy.estimatedTotalAssets())).to.be.greaterThan(
            0
        );
        await strategy.overrideEstimatedTotalAssets(0);
        expect(Number(await strategy.estimatedTotalAssets())).to.be.equal(0);
        await strategy.connect(deployer).harvest();

        const curveLPStakedAfter = await strategy.balanceOfCurveLPStaked();
        expect(Number(curveLPStakedBefore)).to.be.not.greaterThan(
            Number(curveLPStakedAfter)
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
            strategy.connect(deployer)["sweep(address)"](TOKENS.CRV.address)
        ).to.be.revertedWith("!protected");
        await expect(
            strategy.connect(deployer)["sweep(address)"](TOKENS.CVX.address)
        ).to.be.revertedWith("!protected");
        await expect(
            strategy.connect(deployer)["sweep(address)"](TOKENS.FXS.address)
        ).to.be.revertedWith("!protected");
        await expect(
            strategy
                .connect(deployer)
                ["sweep(address)"](TOKENS.CURVE_FXS_LP.address)
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

        const FXSStrategy = await ethers.getContractFactory("FXSStrategy");
        const newStrategy = await upgrades.deployProxy(
            FXSStrategy,
            [vault.address, deployer.address],
            {
                initializer: "initialize",
                kind: "transparent",
                constructorArgs: [vault.address],
                unsafeAllow: ["constructor"],
            }
        );
        await newStrategy.deployed();

        const curveLPStaked = await strategy.balanceOfCurveLPStaked();

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
        expect(Number(await strategy.balanceOfCurveLPStaked())).to.be.equal(0);
        expect(Number(await newStrategy.balanceOfCurveLPStaked())).to.be.equal(
            0
        );
        expect(Number(await want.balanceOf(newStrategy.address))).to.be.equal(
            0
        );
        expect(Number(await strategy.balanceOfCurveLPUnstaked())).to.be.equal(
            0
        );
        expect(
            Number(await newStrategy.balanceOfCurveLPUnstaked())
        ).to.be.equal(Number(curveLPStaked));

        await newStrategy.harvest();

        expect(Number(await strategy.balanceOfCurveLPStaked())).to.be.equal(0);
        expect(Number(await newStrategy.balanceOfCurveLPStaked())).to.be.equal(
            Number(curveLPStaked)
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
        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.constants.Zero,
            ethers.utils.parseUnits("10", 6)
        );
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

        const crvRewards = await strategy.balanceOfCrvRewards();
        expect(Number(crvRewards)).to.be.greaterThan(0);
        expect(
            Number(await strategy.balanceOfCvxRewards(crvRewards))
        ).to.be.greaterThan(0);
    });
});
