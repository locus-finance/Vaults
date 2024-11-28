const {
  loadFixture,
  reset,
} = require("@nomicfoundation/hardhat-network-helpers");
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { expect } = require("chai");
const { utils } = require("ethers");
const { ethers } = require("hardhat");

const { getEnv } = require("../../scripts/utils");

const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

const ETH_NODE_URL = getEnv("ETH_NODE");
const ETH_FORK_BLOCK = getEnv("ETH_FORK_BLOCK");

upgrades.silenceWarnings();

describe("InjectOnChainVault", function () {
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
    WETH_AURA_BPT: {
      address: "0xCfCA23cA9CA720B6E98E3Eb9B6aa0fFC4a5C08B9",
      decimals: 18,
    },
  };

  async function deployContractAndSetVariables() {
    await reset(ETH_NODE_URL, Number(ETH_FORK_BLOCK));

    const [deployer, governance, treasury, whale] = await ethers.getSigners();
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
    await vault["setDepositLimit(uint256)"](ethers.utils.parseEther("10000"));

    const AuraWETHStrategy = await ethers.getContractFactory(
      "MockAuraWETHStrategy"
    );
    const strategy = await upgrades.deployProxy(
      AuraWETHStrategy,
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
      value: utils.parseEther("50"),
    });

    await token
      .connect(tokenWhale)
      .transfer(address, utils.parseUnits(amountUnscaled, dealToken.decimals));
  }

  const oldVaultAddress = "0xf62A24EbE766d0dA04C9e2aeeCd5E86Fac049B7B";

  const calculateFreeFunds = async (oldVault, blockNumber) => {
    const blockTimestamp = ethers.BigNumber.from(
      (await ethers.provider.getBlock(blockNumber)).timestamp
    );
    const lastReport = await oldVault.lastReport();
    const lockedProfitDegradation = await oldVault.lockedProfitDegradation();
    const lockedFundsRatio = blockTimestamp
      .sub(lastReport)
      .mul(lockedProfitDegradation);
    const DEGRADATION_COEFFICIENT = ethers.utils.parseEther("10");

    let lockedProfit = await oldVault.lockedProfit();
    if (lockedFundsRatio.lt(DEGRADATION_COEFFICIENT)) {
      lockedProfit = lockedProfit.sub(
        lockedFundsRatio.mul(lockedProfit).div(DEGRADATION_COEFFICIENT)
      );
    } else {
      lockedProfit = ethers.constants.Zero;
    }

    const totalAssets = await oldVault.totalAssets();
    return totalAssets.sub(lockedProfit);
  };

  it("should make PPS like in old vault and deposit of total supply should be performed", async function () {
    const { vault, whale, want } = await loadFixture(
      deployContractAndSetVariables
    );

    const oldVault = await ethers.getContractAt(
      "OnChainVault",
      oldVaultAddress
    );
    const freeFundsToInject = await calculateFreeFunds(
      oldVault,
      parseInt(ETH_FORK_BLOCK)
    );
    console.log(`Free Funds of an old vault: ${freeFundsToInject.toString()}`);
    const totalSupplyToInject = await oldVault.totalSupply();

    await vault.injectForMigration(totalSupplyToInject, freeFundsToInject);

    await dealTokensToAddress(
      whale.address,
      TOKENS.USDC,
      ethers.utils.formatUnits(totalSupplyToInject, 6)
    );

    await vault.connect(whale)["deposit(uint256)"](totalSupplyToInject);
    expect(await vault.balanceOf(whale.address)).to.be.gt(0);

    expect(await vault.pricePerShare()).to.be.equal(
      await oldVault.pricePerShare()
    );
  });
});
