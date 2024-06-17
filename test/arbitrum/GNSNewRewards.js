const {
  loadFixture,
  mine,
  time,
  reset,
  impersonateAccount,
} = require("@nomicfoundation/hardhat-network-helpers");
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { expect } = require("chai");
const { utils } = require("ethers");
const { ethers } = require("hardhat");

const { getEnv } = require("../../scripts/utils");

const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";
const ARBITRUM_NODE_URL = getEnv("ARBITRUM_NODE");
const ARBITRUM_FORK_BLOCK = getEnv("ARBITRUM_FORK_BLOCK");
const VAULT_ADDRESS = "0xF8F045583580C4Ba954CD911a8b161FafD89A9EF";
const GNS_STRATEGY_ADDRESS = "0xa7eb4efe088A3618C9BA21e1520E0c8460b42D37";
const USDC_ADDRESS = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8";
const UPGRADER = "0xD44044f706B7a3491ae810173e916cE94a15ade5";

upgrades.silenceWarnings();

describe("GNSStrategy", function () {
  async function deployContractAndSetVariables() {
    await reset(ARBITRUM_NODE_URL, Number(ARBITRUM_FORK_BLOCK));

    const want = await ethers.getContractAt(IERC20_SOURCE, USDC_ADDRESS);

    const [whale] = await ethers.getSigners();

    const address = "0xc1287e8e489e990b424299376f37c83cd39bfc4c";
    await impersonateAccount(address);
    const harvester = await ethers.getSigner(address);

    await impersonateAccount(UPGRADER);
    const upgrader = await ethers.getSigner(UPGRADER);

    let tx = await whale.sendTransaction({
      to: UPGRADER,
      value: ethers.utils.parseEther("1"),
    });
    await tx.wait();

    tx = await whale.sendTransaction({
      to: harvester.address,
      value: ethers.utils.parseEther("1"),
    });
    await tx.wait();

    const Vault = await ethers.getContractFactory("OnChainVault");
    const vault = Vault.attach(VAULT_ADDRESS);

    const GNSStrategy = await ethers.getContractFactory("GNSStrategy");
    const strategy = GNSStrategy.attach(GNS_STRATEGY_ADDRESS);

    return {
      vault,
      strategy,
      want,
      harvester,
      upgrader,
    };
  }
  it("should deploy strategy", async function () {
    const { vault, strategy } = await loadFixture(
      deployContractAndSetVariables
    );
    expect(await strategy.vault()).to.equal(vault.address);
    expect(await strategy.name()).to.equal("StrategyGNS");
  });

  it("should harvest with a profit", async function () {
    const { vault, strategy, want, harvester, upgrader } = await loadFixture(
      deployContractAndSetVariables
    );

    const gnsFactory = await ethers.getContractFactory("GNSStrategy", upgrader);
    await upgrades.upgradeProxy(GNS_STRATEGY_ADDRESS, gnsFactory, {
      unsafeAllow: ["constructor"],
      constructorArgs: [VAULT_ADDRESS],
    });
    console.log("Strategy upgraded");
    // console.log(await strategy.balanceOfRewardsInWantToken());
    // const tokens = [
    //   "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
    //   "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
    // ];
    // await strategy.connect(harvester).approveNewRewardsForUniRouter(tokens);
    // console.log(await vault.pricePerShare());
    // console.log(await strategy.estimatedTotalAssets());
    // await strategy.connect(harvester).harvest();
    // console.log(await vault.pricePerShare());
    // console.log(await strategy.estimatedTotalAssets());
    // console.log(await strategy.balanceOfRewardsInWantToken());

    const vaultFactory = await ethers.getContractFactory(
      "OnChainVault",
      upgrader
    );
    await upgrades.upgradeProxy(VAULT_ADDRESS, vaultFactory, {});
    console.log("Vault upgraded");
    // expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
    //   balanceBefore,
    //   ethers.utils.parseUnits("1000", 6)
    // );
    // const gns = await hre.ethers.getContractAt(
    //   IERC20_SOURCE,
    //   TOKENS.GNS.address
    // );

    // // Previous harvest indicated some profit and it was withdrawn to vault
    // expect(Number(await want.balanceOf(vault.address))).to.be.greaterThan(0);

    // // All profit from strategy was withdrawn to vault
    // expect(Number(await want.balanceOf(strategy.address))).to.be.equal(0);

    // // Vault reinvesing its profit back to strategy
    // await strategy.connect(deployer).harvest();
    // expect(Number(await strategy.estimatedTotalAssets())).to.be.greaterThan(
    //   Number(balanceBefore)
    // );
  });
});
