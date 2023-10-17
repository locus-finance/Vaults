const {
    loadFixture,
    mine,
    reset,
    time,
} = require("@nomicfoundation/hardhat-network-helpers");
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { expect } = require("chai");
const { BigNumber, constants } = require("ethers");
const { ethers } = require("hardhat");

const { getEnv } = require("../scripts/utils");

const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

const usdt = "0xdac17f958d2ee523a2206206994597c13d831ec7";
const dai = "0x6b175474e89094c44da98b954eedeac495271d0f";
const bal = "0xba100000625a3754423978a60c9317c58a424e3D";
const aura = "0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF";
const bRethStable = "0x1E19CF2D73a72Ef1332C882F20534B6519Be0276";
const auraBRethStable = "0xDd1fE5AD401D4777cE89959b7fa587e569Bf125D";

const ETH_NODE_URL = getEnv("ETH_NODE");
const ETH_FORK_BLOCK = getEnv("ETH_FORK_BLOCK");

upgrades.silenceWarnings();

describe("RocketAuraStrategy", function () {
    const TOKENS = {
        USDT: {
            address: "0xdac17f958d2ee523a2206206994597c13d831ec7",
            whale: "0x461249076b88189f8ac9418de28b365859e46bfd",
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
        RETH: {
            address: "0xae78736Cd615f374D3085123A210448E74Fc6393",
            whale: "0x7C5aaA2a20b01df027aD032f7A768aC015E77b86",
            decimals: 18,
        },
        AURA: {
            address: "0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF",
            whale: "0x39D787fdf7384597C7208644dBb6FDa1CcA4eBdf",
            decimals: 18,
        },
        BAL: {
            address: "0xba100000625a3754423978a60c9317c58a424e3D",
            whale: "0x10a19e7ee7d7f8a52822f6817de8ea18204f2e4f",
            decimals: 18,
        },
    };

    async function deployContractAndSetVariables() {
        await reset(ETH_NODE_URL, Number(ETH_FORK_BLOCK));

        const [deployer, governance, treasury, whale] =
            await ethers.getSigners();
        const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
        const want = await ethers.getContractAt("IWETH", WETH_ADDRESS);
        await want
            .connect(whale)
            .deposit({ value: ethers.utils.parseEther("10") });

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

        const RocketAuraStrategy = await ethers.getContractFactory(
            "RocketAuraStrategy"
        );
        const strategy = await upgrades.deployProxy(
            RocketAuraStrategy,
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
            value: ethers.utils.parseEther("0.5"),
        });

        await token
            .connect(tokenWhale)
            .transfer(
                address,
                ethers.utils.parseUnits(amountUnscaled, dealToken.decimals)
            );
    }

    it("should deploy strategy", async function () {
        const { vault, strategy } = await loadFixture(
            deployContractAndSetVariables
        );
        expect(await strategy.vault()).to.equal(vault.address);
    });

    it("should harvest with a profit", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        // await vault.setLockedProfitDegradation(ethers.utils.parseEther("1"));
        const balanceBefore = await want.balanceOf(whale.address);

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
        const estimatedBefore = await strategy.estimatedTotalAssets();

        expect(estimatedBefore).to.be.closeTo(
            ethers.utils.parseEther("10"),
            ethers.utils.parseEther("0.025")
        );

        await dealTokensToAddress(strategy.address, TOKENS.BAL, "200");
        await strategy.harvest();

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

    it("should fail harvest with small bpt slippage", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        const balanceBefore = await want.balanceOf(whale.address);

        await strategy.connect(deployer)["setBptSlippage(uint256)"](9999);
        await want
            .connect(whale)
            .approve(vault.address, ethers.utils.parseEther("10"));
        await vault
            .connect(whale)
        ["deposit(uint256)"](ethers.utils.parseEther("10"));
        expect(await want.balanceOf(vault.address)).to.equal(
            ethers.utils.parseEther("10")
        );
        await expect(strategy.connect(deployer).harvest()).to.be.reverted;

        await strategy.connect(deployer)["setBptSlippage(uint256)"](9900);
        await strategy.connect(deployer).harvest();
        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("10"),
            ethers.utils.parseEther("0.025")
        );
    });

    it("should fail harvest with small rewards slippage", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        const balanceBefore = await want.balanceOf(whale.address);

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

        await strategy.connect(deployer)["setRewardsSlippage(uint256)"](9700);
        await strategy.connect(deployer).harvest();
        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("10"),
            ethers.utils.parseEther("0.0025")
        );
    });

    it("should withdraw requested amount", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        const balanceBefore = await want.balanceOf(whale.address);

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
        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("10"),
            ethers.utils.parseEther("0.025")
        );

        await strategy.connect(deployer).harvest();
        await vault.connect(whale)["withdraw(uint256,address,uint256)"](
            ethers.utils.parseEther("10"),
            whale.address,
            100 // 1% acceptable loss
        );

        expect(await want.balanceOf(whale.address)).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseEther("0.004")
        );
    });

    it("should withdraw with loss", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        const balanceBefore = await want.balanceOf(whale.address);

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

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("10"),
            ethers.utils.parseEther("0.025")
        );

        await strategy.connect(deployer).tend();

        await vault.connect(whale)["withdraw(uint256,address,uint256)"](
            ethers.utils.parseEther("10"),
            whale.address,
            1000 // 0.05% acceptable loss
        );

        expect(await want.balanceOf(whale.address)).to.be.closeTo(
            balanceBefore,
            ethers.utils.parseEther("0.004")
        );
    });

    it("should not withdraw with loss", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        await want
            .connect(whale)
            .approve(vault.address, ethers.utils.parseEther("10"));
        await vault
            .connect(whale)
        ["deposit(uint256)"](ethers.utils.parseEther("10"));

        const balanceBefore = await want.balanceOf(whale.address);

        expect(await want.balanceOf(vault.address)).to.equal(
            ethers.utils.parseEther("10")
        );

        await strategy.connect(deployer).harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("10"),
            ethers.utils.parseEther("0.025")
        );

        await strategy.connect(deployer).tend();

        await expect(
            vault.connect(whale)["withdraw(uint256,address,uint256)"](
                ethers.utils.parseEther("10"),
                whale.address,
                0 // 0% acceptable loss
            )
        ).to.be.reverted;

        expect(await want.balanceOf(whale.address)).to.equal(balanceBefore);
    });

    it("should emergency exit", async function () {
        const { vault, strategy, whale, want } = await loadFixture(
            deployContractAndSetVariables
        );

        const oneEther = ethers.utils.parseEther("1");
        await want.connect(whale).approve(vault.address, oneEther);
        await vault.connect(whale)["deposit(uint256)"](oneEther);
        expect(await want.balanceOf(vault.address)).to.equal(oneEther);

        await strategy.harvest();
        mine(100);

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            oneEther,
            ethers.utils.parseEther("0.0025")
        );

        await strategy.setEmergencyExit();
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.equal(0);
        expect(await want.balanceOf(vault.address)).to.be.closeTo(
            oneEther,
            ethers.utils.parseEther("0.0025")
        );
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
            strategy.connect(deployer)["sweep(address)"](bRethStable)
        ).to.be.revertedWith("!protected");
        await expect(
            strategy.connect(deployer)["sweep(address)"](auraBRethStable)
        ).to.be.revertedWith("!protected");
        await expect(
            strategy.connect(deployer)["sweep(address)"](aura)
        ).to.be.revertedWith("!protected");
        await expect(
            strategy.connect(deployer)["sweep(address)"](bal)
        ).to.be.revertedWith("!protected");

        const daiToken = await hre.ethers.getContractAt(IERC20_SOURCE, dai);
        const daiWhaleAddress = "0x60faae176336dab62e284fe19b885b095d29fb7f";
        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [daiWhaleAddress],
        });
        const daiWhale = await ethers.getSigner(daiWhaleAddress);

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
        mine(100);
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("0.5"),
            ethers.utils.parseEther("0.0025")
        );

        await vault
            .connect(deployer)
        ["updateStrategyDebtRatio(address,uint256)"](
            strategy.address,
            10000
        );
        mine(100);
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("1"),
            ethers.utils.parseEther("0.0025")
        );

        await vault
            .connect(deployer)
        ["updateStrategyDebtRatio(address,uint256)"](
            strategy.address,
            5000
        );
        mine(100);
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("0.5"),
            ethers.utils.parseEther("0.0025")
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
        mine(100);

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("1"),
            ethers.utils.parseEther("0.0025")
        );

        const RocketAuraStrategy = await ethers.getContractFactory(
            "RocketAuraStrategy"
        );
        const newStrategy = await upgrades.deployProxy(
            RocketAuraStrategy,
            [vault.address, deployer.address],
            {
                initializer: "initialize",
                kind: "transparent",
                constructorArgs: [vault.address],
                unsafeAllow: ["constructor"],
            }
        );
        await newStrategy.deployed();

        const auraToken = await hre.ethers.getContractAt(IERC20_SOURCE, aura);
        const balToken = await hre.ethers.getContractAt(IERC20_SOURCE, bal);
        const bRethStableToken = await hre.ethers.getContractAt(
            IERC20_SOURCE,
            bRethStable
        );
        const auraBRethStableToken = await hre.ethers.getContractAt(
            IERC20_SOURCE,
            auraBRethStable
        );

        await vault["migrateStrategy(address,address)"](
            strategy.address,
            newStrategy.address
        );

        expect(await strategy.estimatedTotalAssets()).to.be.equal(0);
        expect(await newStrategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("1"),
            ethers.utils.parseEther("0.0025")
        );
        expect(
            Number(await auraToken.balanceOf(newStrategy.address))
        ).to.be.greaterThan(0);
        expect(
            Number(await balToken.balanceOf(newStrategy.address))
        ).to.be.greaterThan(0);
        expect(
            Number(await bRethStableToken.balanceOf(newStrategy.address))
        ).to.be.greaterThan(0);
        expect(
            Number(await auraBRethStableToken.balanceOf(newStrategy.address))
        ).to.be.equal(0);

        mine(100);
        await newStrategy.harvest();

        expect(
            Number(await auraToken.balanceOf(newStrategy.address))
        ).to.be.equal(0);
        expect(
            Number(await balToken.balanceOf(newStrategy.address))
        ).to.be.equal(0);
        expect(
            Number(await bRethStableToken.balanceOf(newStrategy.address))
        ).to.be.equal(0);
        expect(
            Number(await auraBRethStableToken.balanceOf(newStrategy.address))
        ).to.be.greaterThan(0);

        expect(await newStrategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("1"),
            ethers.utils.parseEther("0.0025")
        );
    });

    it("should revoke from vault", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        const oneEther = ethers.utils.parseEther("1");
        await want.connect(whale).approve(vault.address, oneEther);
        await vault.connect(whale)["deposit(uint256)"](oneEther);
        mine(1);
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("1"),
            ethers.utils.parseEther("0.0025")
        );

        await vault["revokeStrategy(address)"](strategy.address);
        mine(100);
        await strategy.harvest();
        expect(await want.balanceOf(vault.address)).to.be.closeTo(
            oneEther,
            ethers.utils.parseEther("0.0025")
        );
    });

    it("should withdraw on vault shutdown", async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(
            deployContractAndSetVariables
        );

        const oneEther = ethers.utils.parseEther("1");
        await want.connect(whale).approve(vault.address, oneEther);
        await vault.connect(whale)["deposit(uint256)"](oneEther);
        expect(await want.balanceOf(vault.address)).to.equal(oneEther);

        if ((await want.balanceOf(whale.address)) > 0) {
            want.connect(whale).transfer(
                ZERO_ADDRESS,
                await want.balanceOf(whale.address)
            );
        }
        await strategy.harvest();
        mine(3600 * 7);

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther("1"),
            ethers.utils.parseEther("0.0025")
        );

        await vault["setEmergencyShutdown(bool)"](true);
        mine(1);
        await vault.connect(whale)["withdraw(uint256,address,uint256)"](
            ethers.utils.parseEther("1"),
            whale.address,
            5 // 0.05% acceptable loss
        );
        expect(await want.balanceOf(whale.address)).to.be.closeTo(
            oneEther,
            ethers.utils.parseEther("0.0025")
        );
    });

    it("should scale decimals", async function () {
        const { vault } = await loadFixture(deployContractAndSetVariables);

        const TestScaler = await ethers.getContractFactory("TestScaler");
        const testScaler = await TestScaler.deploy(vault.address);
        await testScaler.deployed();

        expect(
            await testScaler.scaleDecimals(
                ethers.utils.parseEther("1"),
                usdt,
                bal
            )
        ).to.be.equal(BigNumber.from("1000000000000000000000000000000"));

        expect(
            await testScaler.scaleDecimals(
                ethers.utils.parseEther("1"),
                bal,
                usdt
            )
        ).to.be.equal(BigNumber.from("1000000"));

        expect(
            await testScaler.scaleDecimals(
                ethers.utils.parseEther("1"),
                bal,
                dai
            )
        ).to.be.equal(BigNumber.from("1000000000000000000"));
    });

    it("should not get aura rewards after inflation protection time", async function () {
        const { strategy } = await loadFixture(deployContractAndSetVariables);
        const snapshotId = await network.provider.send("evm_snapshot");

        const TestAuraMath = await hre.ethers.getContractFactory(
            "TestAuraMath"
        );
        const testAuraMath = await TestAuraMath.deploy();
        await testAuraMath.deployed();

        const iAuraToken = await ethers.getContractAt("IAuraToken", aura);
        const minter = await iAuraToken.minter();
        const iAuraMinter = await ethers.getContractAt("IAuraMinter", minter);
        const inflationProtectionTime =
            await iAuraMinter.inflationProtectionTime();

        await time.setNextBlockTimestamp(inflationProtectionTime);
        mine(2);

        expect(
            await testAuraMath.convertCrvToCvx(ethers.utils.parseEther("1"))
        ).to.be.equal(0);

        await network.provider.send("evm_revert", [snapshotId]);
    });

    it("should change AURA PID and AURA rewards", async function () {
        const { strategy, whale, deployer } = await loadFixture(
            deployContractAndSetVariables
        );

        expect(await strategy.AURA_PID()).to.be.equal(109);
        await expect(strategy.connect(whale)["setAuraPid(uint256)"](200)).to.be
            .reverted;
        await strategy.connect(deployer)["setAuraPid(uint256)"](200);
        expect(await strategy.AURA_PID()).to.be.equal(200);

        expect(
            (await strategy.auraBRethStable()).toLocaleLowerCase()
        ).to.be.equal(auraBRethStable.toLocaleLowerCase());
        await expect(
            strategy
                .connect(whale)
            ["setAuraBRethStable(address)"](constants.AddressZero)
        ).to.be.reverted;
        await strategy
            .connect(deployer)
        ["setAuraBRethStable(address)"](constants.AddressZero);
        expect(await strategy.auraBRethStable()).to.be.equal(
            constants.AddressZero
        );
    });
});
