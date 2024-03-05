const {
  loadFixture,
  mine,
  time,
  reset,
} = require("@nomicfoundation/hardhat-network-helpers");
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { expect } = require("chai");
const { utils } = require("ethers");
const { ethers } = require("hardhat");

const { getEnv } = require("../../scripts/utils");

const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";
const ARBITRUM_NODE_URL = getEnv("ARBITRUM_NODE");
const ARBITRUM_FORK_BLOCK = getEnv("ARBITRUM_FORK_BLOCK");

upgrades.silenceWarnings();

describe("GNSStrategy", function () {
  const TOKENS = {
    USDC: {
      address: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
      whale: "0x62383739D68Dd0F844103Db8dFb05a7EdED5BBE6",
      decimals: 6,
    },
    ETH: {
      address: ZERO_ADDRESS,
      whale: "0xF977814e90dA44bFA03b6295A0616a897441aceC",
      decimals: 18,
    },
    WETH: {
      address: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
      whale: "0x940a7ed683a60220de573ab702ec8f789ef0a402",
      decimals: 18,
    },
    USDT: {
      address: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9",
      whale: "0xf89d7b9c864f589bbF53a82105107622B35EaA40",
      decimals: 18,
    },
    GNS: {
      address: "0x18c11fd286c5ec11c3b683caa813b77f5163a122",
      whale: "0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D",
      decimals: 18,
    },
    DAI: {
      address: "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1",
      whale: "0x2d070ed1321871841245d8ee5b84bd2712644322",
      decimals: 18,
    },
  };

  async function deployContractAndSetVariables() {
    await reset(ARBITRUM_NODE_URL, Number(ARBITRUM_FORK_BLOCK));

    const [deployer, governance, treasury, whale] = await ethers.getSigners();
    const USDC_ADDRESS = TOKENS.USDC.address;
    const want = await ethers.getContractAt(IERC20_SOURCE, USDC_ADDRESS);

    const name = "lvAYI";
    const symbol = "vaDeFi";
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

    const GNSStrategy = await ethers.getContractFactory("GNSStrategy");
    const strategy = await upgrades.deployProxy(
      GNSStrategy,
      [vault.address, deployer.address],
      {
        initializer: "initialize",
        kind: "transparent",
        constructorArgs: [vault.address],
        unsafeAllow: ["constructor"],
      }
    );
    await strategy.deployed();

    // await vault["addStrategy(address,uint256,uint256,uint256,uint256)"](
    //     strategy.address,
    //     10000,
    //     0,
    //     ethers.utils.parseEther("10000"),
    //     0
    // );
    await vault["addStrategy(address,uint256,uint256)"](
      strategy.address,
      10000,
      0
    );

    await dealTokensToAddress(whale.address, TOKENS.USDC, "1000");
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
      value: utils.parseEther("0.5"),
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
    expect(await strategy.name()).to.equal("StrategyGNS");
  });

  it("should get reasonable prices from oracle", async function () {
    const { strategy } = await loadFixture(deployContractAndSetVariables);
    const oneUnit = ethers.utils.parseEther("1");
    const ethPrice = await strategy.ethToWant(ethers.utils.parseEther("1"));
    expect(Number(ethPrice)).to.be.greaterThan(0);
    expect(Number(await strategy.gnsToWant(oneUnit))).to.be.greaterThan(0);
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
      ethers.utils.parseUnits("1000", 6)
    );
    const gns = await hre.ethers.getContractAt(
      IERC20_SOURCE,
      TOKENS.GNS.address
    );

    // simulate profit
    await dealTokensToAddress(strategy.address, TOKENS.DAI, "50");
    await strategy.connect(deployer).harvest();

    // Previous harvest indicated some profit and it was withdrawn to vault
    expect(Number(await want.balanceOf(vault.address))).to.be.greaterThan(0);

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

    await strategy.connect(deployer).harvest();

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

  it("should fail harvest with small slippage", async function () {
    const { vault, strategy, whale, deployer, want } = await loadFixture(
      deployContractAndSetVariables
    );

    await strategy.connect(deployer)["setSlippage(uint256)"](9999);
    await want
      .connect(whale)
      .approve(vault.address, ethers.utils.parseUnits("1000", 6));
    await vault
      .connect(whale)
      ["deposit(uint256)"](ethers.utils.parseUnits("1000", 6));
    expect(await want.balanceOf(vault.address)).to.equal(
      ethers.utils.parseUnits("1000", 6)
    );
    await expect(strategy.connect(deployer).harvest()).to.be.reverted;
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
      strategy.connect(deployer)["sweep(address)"](TOKENS.GNS.address)
    ).to.be.revertedWith("!protected");
    await expect(
      strategy.connect(deployer)["sweep(address)"](TOKENS.WETH.address)
    ).to.be.revertedWith("!protected");
    await expect(
      strategy.connect(deployer)["sweep(address)"](TOKENS.DAI.address)
    ).to.be.revertedWith("!protected");

    const usdtToken = await hre.ethers.getContractAt(
      IERC20_SOURCE,
      TOKENS.USDT.address
    );
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [TOKENS.USDT.whale],
    });
    const usdtWhale = await ethers.getSigner(TOKENS.USDT.whale);

    await usdtToken
      .connect(usdtWhale)
      .transfer(strategy.address, ethers.utils.parseUnits("10", 6));
    expect(TOKENS.DAI.address).not.to.be.equal(await strategy.want());
    await expect(() =>
      strategy.connect(deployer)["sweep(address)"](usdtToken.address)
    ).to.changeTokenBalances(
      usdtToken,
      [strategy, deployer],
      [ethers.utils.parseUnits("-10", 6), ethers.utils.parseUnits("10", 6)]
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
      ["updateStrategyDebtRatio(address,uint256)"](strategy.address, 5000);
    mine(1);
    await strategy.harvest();
    expect(Number(await strategy.estimatedTotalAssets())).to.be.closeTo(
      ethers.utils.parseUnits("500", 6),
      ethers.utils.parseUnits("50", 6)
    );

    await vault
      .connect(deployer)
      ["updateStrategyDebtRatio(address,uint256)"](strategy.address, 10000);
    mine(1);
    await strategy.harvest();
    expect(Number(await strategy.estimatedTotalAssets())).to.be.closeTo(
      ethers.utils.parseUnits("1000", 6),
      ethers.utils.parseUnits("100", 6)
    );

    await vault
      .connect(deployer)
      ["updateStrategyDebtRatio(address,uint256)"](strategy.address, 5000);
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

    const GNSToken = await hre.ethers.getContractAt(
      IERC20_SOURCE,
      TOKENS.GNS.address
    );

    const GNSStrategy = await ethers.getContractFactory("GNSStrategy");
    const newStrategy = await upgrades.deployProxy(
      GNSStrategy,
      [vault.address, deployer.address],
      {
        initializer: "initialize",
        kind: "transparent",
        constructorArgs: [vault.address],
        unsafeAllow: ["constructor"],
      }
    );
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
    expect(Number(await want.balanceOf(newStrategy.address))).to.be.equal(0);
    expect(Number(await GNSToken.balanceOf(strategy.address))).to.be.equal(0);
    expect(
      Number(await GNSToken.balanceOf(newStrategy.address))
    ).to.be.greaterThan(0);
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
