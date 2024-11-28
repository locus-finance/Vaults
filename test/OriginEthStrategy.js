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
  const { ethers, upgrades } = require("hardhat");

  
  const { getEnv } = require("../scripts/utils");
  
  const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";
  
  const ETH_NODE = getEnv("ETH_NODE");
  const ETH_FORK_BLOCK = getEnv("ETH_FORK_BLOCK");
  
  // upgrades.silenceWarnings();
  
  describe("OriginEthStrategy", function () {
    const TOKENS = {
      ETH: {
        address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
        whale: "0x2fEb1512183545f48f6b9C5b4EbfCaF49CfCa6F3",
        ethWhale: "0xcA8Fa8f0b631EcdB18Cda619C4Fc9d197c8aFfCa"
      },
    };
  
    // const STABLE_JOE_STAKING = "0x43646A8e839B2f2766392C1BF8f60F6e587B6960";
  
    async function deployContractAndSetVariables() {
      await reset(ETH_NODE, Number(ETH_FORK_BLOCK));
      const [deployer, governance, treasury, whale] = await ethers.getSigners();
      const WETH_ADDRESS = TOKENS.ETH.address;
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
      const OriginStrategy = await ethers.getContractFactory("OriginEthStrategy");
      const strategy = await upgrades.deployProxy(
        OriginStrategy,
        [vault.address, deployer.address],
        {
          kind: "uups",
          unsafeAllow: ["constructor"],
          constructorArgs: [vault.address],
        }
      );
      await strategy.deployed();
        
      await vault["addStrategy(address,uint256,uint256,uint256,uint256)"](
        strategy.address,
        10000,
        0,
        0,
        parseEther("10000")
      );
  
      await dealTokensToAddress(whale.address, TOKENS.ETH, "10");
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
        params: [TOKENS.ETH.ethWhale],
      });
      const ethWhale = await ethers.getSigner(TOKENS.ETH.ethWhale);
      let tx = await ethWhale.sendTransaction({
        to: tokenWhale.address,
        value: utils.parseEther("10"),
      });
      await tx.wait();
      tx = await token
        .connect(tokenWhale)
        .transfer(address, utils.parseUnits(amountUnscaled, dealToken.decimals));
        await tx.wait()
    }
    it("should deploy strategy", async function () {
      const { vault, strategy } = await loadFixture(
        deployContractAndSetVariables
      );
      expect(await strategy.vault()).to.equal(vault.address);
      expect(await strategy.name()).to.equal("Origin ETH Strategy");
    });
  
    it("should get reasonable prices from oracle", async function () {
      const { strategy } = await loadFixture(deployContractAndSetVariables);
      const oneUnit = utils.parseEther("1");
  
      expect(Number(await strategy.LPToWant(oneUnit))).to.be.greaterThan(0);
      expect(Number(await strategy.CrvToWant(oneUnit))).to.be.greaterThan(0);
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
        ethers.utils.parseUnits("10", 17)
      );
      const etaBefore = await strategy.estimatedTotalAssets()
      // We are dropping some USDC to staking contract to simulate profit from JOE staking
      await dealTokensToAddress(whale.address, TOKENS.ETH, "1000");
    //   await ethers.provider.send('evm_increaseTime', [100 * 24 * 60 * 60])
      
      // expect(Number(await strategy.rewardss())).to.be.greaterThan(0);
  
      await ethers.provider.send("evm_increaseTime", [50 * 24 * 60 * 60]);
      // Vault reinvesing its profit back to strategy
      await strategy.connect(deployer).harvest();
      expect(Number(await strategy.estimatedTotalAssets())).to.be.greaterThan(
        Number(etaBefore)
      );
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
        ethers.utils.parseUnits("1", 17)
      );
      await ethers.provider.send("evm_increaseTime", [20 * 24 * 60 * 60]);
  
      await vault
        .connect(whale)
        ["withdraw(uint256,address,uint256)"](
          await vault.balanceOf(whale.address),
          whale.address,
          1000
        );
      expect((await want.balanceOf(whale.address))).to.be.closeTo(
        (balanceBefore),
        ethers.utils.parseUnits("1", 17)
      );
  
      const newWhaleBalance = await want.balanceOf(whale.address);
      await vault.connect(whale)["deposit(uint256)"](newWhaleBalance);
      expect((await want.balanceOf(whale.address))).to.be.equal(0);
      await ethers.provider.send("evm_increaseTime", [20 * 24 * 60 * 60]);
  
      await strategy.harvest();
      await dealTokensToAddress(strategy.address, TOKENS.ETH, "1000");
      await vault
        .connect(whale)
        ["withdraw(uint256,address,uint256)"](
          await vault.balanceOf(whale.address),
          whale.address,
          1000
        );
      expect((await want.balanceOf(whale.address))).to.be.closeTo(
        newWhaleBalance,
        ethers.utils.parseUnits("1", 17)
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
        ethers.utils.parseUnits("1", 17)
      );
      await ethers.provider.send("evm_increaseTime", [20 * 24 * 60 * 60]);
  
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
        ethers.utils.parseUnits("1", 17)
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
        ethers.utils.parseUnits("1", 17)
      );
  
      await strategy.setEmergencyExit();
      await strategy.harvest();
  
      expect(await strategy.estimatedTotalAssets()).to.equal(0);
      expect((await want.balanceOf(vault.address))).to.be.closeTo(
        balanceBefore,
        ethers.utils.parseUnits("1", 17)
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
        ethers.utils.parseUnits("1", 17)
      );
  
      const JOEStrategy = await ethers.getContractFactory("OriginEthStrategy");
      const newStrategy = await upgrades.deployProxy(
        JOEStrategy,
        [vault.address, deployer.address],
        {
          initializer: "initialize",
          kind: "uups",
          constructorArgs: [vault.address],
          unsafeAllow: ["constructor"],
        }
      );
      await newStrategy.deployed();
  
      const joeStaked = await strategy.balanceOfLPStaked();
  
      await vault["migrateStrategy(address,address)"](
        strategy.address,
        newStrategy.address
      );
  
      expect(await strategy.estimatedTotalAssets()).to.be.equal(0);
      expect(await newStrategy.estimatedTotalAssets()).to.be.closeTo(
        balanceBefore,
        ethers.utils.parseUnits("1", 17)
      );
  
      expect((await want.balanceOf(strategy.address))).to.be.equal(0);
      expect((await strategy.balanceOfLPStaked())).to.be.equal(0);
      expect((await newStrategy.balanceOfLPStaked())).to.be.equal(0);
  
      expect((await want.balanceOf(newStrategy.address))).to.be.closeTo(
        balanceBefore,
        ethers.utils.parseUnits("1", 17)
      );
  
      expect((await strategy.balanceOfWant())).to.be.equal(0);
      expect((await newStrategy.balanceOfWant())).to.be.closeTo(
        balanceBefore,
        ethers.utils.parseUnits("1", 17)
      );
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
        ethers.utils.parseUnits("1", 17)
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
        ethers.utils.parseUnits("1", 17)
      );
    });
  });
  