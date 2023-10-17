const {
  loadFixture,
  reset,
} = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { utils, BigNumber } = require("ethers");
const { ethers } = require("hardhat");
const { getEnv } = require("../../vaultsV2/scripts/utils/env");
const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";
const ETH_NODE = getEnv("ETH_NODE");
const ETHEREUM_FORK_BLOCK = getEnv("ETHEREUM_FORK_BLOCK");
const VAULT_V1 = "0x3edbE670D03C4A71367dedA78E73EA4f8d68F2E4";

const VAULT_V1_ABI = [
  "function balanceOf(address) external view returns (uint256)",
  "function symbol() external view returns (string memory)",
  "function withdraw() external",
  "function approve(address,uint256) external",
  "function token() external view returns(address)",
];

const mnemonic =
  "embark uncover mean anger scatter pill team fence energy harvest away topple";

describe("Migration", function () {
  const TOKENS = {
    USDC: {
      address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
      whale: "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503",
      decimals: 6,
    },
    ETH: {
      whale: "0x00000000219ab540356cBB839Cbe05303d7705Fa",
    },
    WETH: {
      address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    },
  };

  async function deployContractAndSetVariables() {
    await reset(ETH_NODE, Number(ETHEREUM_FORK_BLOCK));
    const [deployer, governance, treasury, whale] = await ethers.getSigners();
    const vaultV1 = await ethers.getContractAt(VAULT_V1_ABI, VAULT_V1);
    const want = await ethers.getContractAt(IERC20_SOURCE, TOKENS.WETH.address);
    const VaultV2 = await ethers.getContractFactory("VaultMock");
    const vaultV2 = await VaultV2.deploy(TOKENS.WETH.address);
    await vaultV2.deployed();

    const wallets = [];
    const walletsPK = [];
    const node = ethers.utils.HDNode.fromMnemonic(mnemonic);

    for (let i = 0; i < 20; i++) {
      const path = "m/44'/60'/0'/0/" + i;
      const wallet = node.derivePath(path);
      wallets.push(wallet.address);
      walletsPK.push(wallet.privateKey);
    }

    const Migration = await ethers.getContractFactory("Migration");
    const migration = await Migration.deploy(
      vaultV1.address,
      vaultV2.address,
      wallets.slice(0, 10),
      treasury.address
    );
    await migration.deployed();

    await dealTokensToAddress(whale.address, TOKENS.USDC, "1000");
    for (let index = 0; index < 10; index++) {
      const wal = new ethers.Wallet(walletsPK[index], ethers.provider);
      await vaultV1
        .connect(wal)
        .approve(migration.address, ethers.constants.MaxUint256);
    }

    return {
      vaultV1,
      vaultV2,
      migration,
      deployer,
      whale,
      governance,
      treasury,
      wallets,
      walletsPK,
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

  it("should deploy migration", async function () {
    const { vaultV1, vaultV2, migration, wallets, treasury } =
      await loadFixture(deployContractAndSetVariables);
    expect(await vaultV2.name()).to.equal("MockVault");
    expect(await vaultV2.symbol()).to.equal("MV");
    expect(await vaultV2.token()).to.equal(TOKENS.WETH.address);

    expect(await migration.vaultV1()).to.equal(vaultV1.address);
    expect(await migration.vaultV2()).to.equal(vaultV2.address);

    expect(await migration.treasury()).to.equal(treasury.address);
    for (let index = 0; index < 10; index++) {
      expect(await migration.users(index)).to.equal(wallets[index]);
    }
  });

  it("should add users to migration", async function () {
    const { migration, wallets } = await loadFixture(
      deployContractAndSetVariables
    );
    await migration.addUsers(wallets.slice(10, 20));
    for (let index = 10; index < 20; index++) {
      expect(await migration.users(index)).to.equal(wallets[index]);
    }
  });

  it("should withdraw half of users", async function () {
    const { vaultV1, vaultV2, migration, wallets, treasury } =
      await loadFixture(deployContractAndSetVariables);
    const balancesBefore = [];
    const balancesAfter = [];
    for (let index = 0; index < wallets.length; index++) {
      balancesBefore.push((await vaultV1.balanceOf(wallets[index])).toNumber());
    }
    await migration.addUsers(wallets.slice(10, 20));
    await migration.withdraw();
    for (let index = 0; index < 10; index++) {
      expect((await vaultV1.balanceOf(wallets[index])).toNumber()).to.eq(0);
    }
    for (let index = 10; index < wallets.length; index++) {
      expect((await vaultV1.balanceOf(wallets[index])).toNumber()).to.eq(
        balancesBefore[index]
      );
    }
    for (let index = 0; index < 10; index++) {
      expect(await migration.notWithdrawnUsers(index)).to.eq(
        wallets[index + 10]
      );
    }
  });

  it("should withdraw half of users => deposit => withdrawWithDetectedError => deposit", async function () {
    const { vaultV1, vaultV2, migration, wallets, treasury, want, walletsPK } =
      await loadFixture(deployContractAndSetVariables);
    await migration.addUsers(wallets.slice(10, 20));
    await migration.withdraw();
    expect(await vaultV2.balanceOf(migration.address)).to.eq(0);
    await migration.deposit();
    expect(await vaultV2.balanceOf(migration.address)).to.be.gt(0);
    const balanceAfterFirstDeposit = await vaultV2.balanceOf(migration.address);
    for (let index = 10; index < 15; index++) {
      const wal = new ethers.Wallet(walletsPK[index], ethers.provider);
      await vaultV1
        .connect(wal)
        .approve(migration.address, ethers.constants.MaxUint256);
    }
    await migration.withdrawUsersWithDetectedError();
    await migration.deposit();
    const balanceAfterSecondDeposit = await vaultV2.balanceOf(
      migration.address
    );
    expect(balanceAfterSecondDeposit).to.be.gt(balanceAfterFirstDeposit);
    for (let index = 15; index < 20; index++) {
      const wal = new ethers.Wallet(walletsPK[index], ethers.provider);
      await vaultV1
        .connect(wal)
        .approve(migration.address, ethers.constants.MaxUint256);
    }
    await migration.withdrawUsersWithDetectedError();
    await migration.deposit();
    const balanceAfterThirdDeposit = await vaultV2.balanceOf(migration.address);
    expect(balanceAfterThirdDeposit).to.be.gt(balanceAfterSecondDeposit);
    expect(await want.balanceOf(migration.address)).to.eq(0);
  });

  it("should emergency exit", async function () {
    const { vaultV1, vaultV2, migration, wallets, treasury, want, walletsPK } =
      await loadFixture(deployContractAndSetVariables);
    await migration.addUsers(wallets.slice(10, 20));
    await migration.withdraw();
    expect(await want.balanceOf(migration.address)).to.be.gt(0);
    expect(await want.balanceOf(treasury.address)).to.eq(0);

    await migration.emergencyExit();
    expect(await want.balanceOf(migration.address)).to.eq(0);
    expect(await want.balanceOf(treasury.address)).to.be.gt(0);
  });
});
