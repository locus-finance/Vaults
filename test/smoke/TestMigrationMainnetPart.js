const helpers = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");

const executeDropActionBuilder = require('../../tasks/migration/reusable/executeDrop');
const dropperContractInteractionActionBuilder = require('../../tasks/migration/reusable/steps/dropperContractInteraction');
const migrationContractInteractionActionBuilder = require('../../tasks/migration/reusable/steps/migrationContractInteraction');
const migrationContractPopulationActionBuilder = require('../../tasks/migration/reusable/migrationContractPopulation');
const additionalDropActionBuilder = require('../../tasks/migration/reusable/additionalDrop');


upgrades.silenceWarnings();

const mintNativeTokens = async (signer, amountHex) => {
  await hre.network.provider.send("hardhat_setBalance", [
    signer.address || signer,
    amountHex
  ]);
}

const withImpersonatedSigner = async (signerAddress, action) => {
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [signerAddress],
  });

  const impersonatedSigner = await hre.ethers.getSigner(signerAddress);
  await action(impersonatedSigner);

  await hre.network.provider.request({
    method: "hardhat_stopImpersonatingAccount",
    params: [signerAddress],
  });
}

describe("TestMigrationMainnetPart", () => {
  const beforeMigrationBlock = 18427399;

  const ethVaultMigrationParams = {
    v1vault: "0x3edbE670D03C4A71367dedA78E73EA4f8d68F2E4",
    v2vault: "0x0e86f93145d097090acbbb8ee44c716dacff04d7",
    migration: "0xd25d0de43579223429c28f2d64183a47a79078C7",
    dropper: "0xEB20d24d42110B586B3bc433E331Fe7CC32D1471",
    csv: "./tasks/migration/csv/lvEthV2TokenReceiversReadyForDrop.csv",
    csvNonMigrated: "./tasks/migration/csv/postMigration/nonMigrated/lvEthV1HoldersNonMigrated.csv",
    csvFinalMigration: "./tasks/migration/csv/postMigration/finalMigration/lvEthV2HoldersFinallyMigrated.csv"
  };

  const defiVaultMigrationParams = {
    v1vault: "0xf62A24EbE766d0dA04C9e2aeeCd5E86Fac049B7B",
    v2vault: "0x65b08FFA1C0E1679228936c0c85180871789E1d7",
    migration: "0xf42402303BCA9d5575A8aC7b90CB18026c80354D",
    dropper: "0xEB20d24d42110B586B3bc433E331Fe7CC32D1471",
    csv: "./tasks/migration/csv/lvDciV2TokenReceiversReadyForDrop.csv",
    csvNonMigrated: "./tasks/migration/csv/postMigration/nonMigrated/lvDciV1HoldersNonMigrated.csv",
    csvFinalMigration: "./tasks/migration/csv/postMigration/finalMigration/lvDciV2HoldersFinallyMigrated.csv"
  };
  
  beforeEach(async () => {
    await helpers.reset(
      hre.config.networks.hardhat.forking.url,
      hre.config.networks.hardhat.forking.blockNumber
    );
  });

  xit("should make perform migrations withdraw, inject, deposit, emergencyExit, drop (using fork with real lvETH Vault)", async function () {
    const vault = await ethers.getContractAt(
      "OnChainVault",
      "0x0e86f93145d097090acbbb8ee44c716dacff04d7"
    );
    const migration = await ethers.getContractAt(
      "Migration",
      "0xd25d0de43579223429c28f2d64183a47a79078C7"
    );
    const dropper = await hre.ethers.getContractAt(
      "Dropper",
      "0xEB20d24d42110B586B3bc433E331Fe7CC32D1471"
    );

    const migrationOwner = await migration.owner();
    const vaultOwner = await vault.owner();
    const droppedOwner = await dropper.owner();
    const treasury = await migration.treasury();

    await mintNativeTokens(migrationOwner, "0x10000000000000000000000");
    await mintNativeTokens(vaultOwner, "0x10000000000000000000000");
    await mintNativeTokens(droppedOwner, "0x10000000000000000000000");
    await mintNativeTokens(treasury, "0x10000000000000000000000");

    await withImpersonatedSigner(migrationOwner, async (migrationOwnerSigner) => {
      await migration.connect(migrationOwnerSigner).withdraw();
    });

    if (!(await vault.isInjectedOnce())) {
      console.log(`A vault: ${vault.address} was not injected. Injecting...`);
      await withImpersonatedSigner(vaultOwner, async (vaultOwnerSigner) => {
        const { totalSupplyToInject, freeFundsToInject } = await hre.run("calculateInjectableValuesForLvETH");
        await vault.connect(vaultOwnerSigner).injectForMigration(totalSupplyToInject, freeFundsToInject);
      });
    }

    await withImpersonatedSigner(vaultOwner, async (vaultOwnerSigner) => {
      await vault.connect(vaultOwnerSigner).setDepositLimit(ethers.constants.MaxUint256);
    });

    await withImpersonatedSigner(migrationOwner, async (migrationOwnerSigner) => {
      await migration.connect(migrationOwnerSigner).deposit();
      await migration.connect(migrationOwnerSigner).emergencyExit();
    });

    await withImpersonatedSigner(treasury, async (treasurySigner) => {
      await vault.connect(treasurySigner).transfer(
        dropper.address,
        await vault.balanceOf(treasury)
      );
    });

    console.log(`Actual Dropper balance: ${ethers.utils.formatUnits(await vault.balanceOf(dropper.address))}`);

    const csvFileName = "./tasks/migration/csv/lvEthV2TokenReceiversReadyForDrop.csv";

    const maxAmountOfUsers = await hre.run("countDropReceiversFromMigration", {
      migration: migration.address
    });

    await hre.run('saveDropReceiversFromMigration', {
      migration: migration.address,
      csv: csvFileName,
      count: maxAmountOfUsers
    });

    await withImpersonatedSigner(droppedOwner, async (droppedOwnerSigner) => {
      await executeDropActionBuilder(
        'receiver',
        'balance',
        csvFileName,
        vault.address,
        dropper.address,
        droppedOwnerSigner
      )();
    });
  });

  xit('should perform migrate step tasks successfully', async () => {
    const migrationParams = defiVaultMigrationParams;

    const vault = await ethers.getContractAt(
      "OnChainVault",
      migrationParams.v2vault
    );
    const dropper = await ethers.getContractAt(
      "Dropper",
      migrationParams.dropper
    );
    const migration = await ethers.getContractAt(
      "Migration",
      migrationParams.migration
    );

    const globalOwner = await vault.owner();
    const treasury = await migration.treasury();
    const migrationOwner = await migration.owner();
    const dropperOwner = await dropper.owner();

    await mintNativeTokens(globalOwner, "0xF0000000000000000000000");
    await mintNativeTokens(treasury, "0xF0000000000000000000000");
    
    await withImpersonatedSigner(globalOwner, async (globalOwnerSigner) => {
      await migrationContractInteractionActionBuilder(globalOwnerSigner)({
        v1vault: migrationParams.v1vault,
        v2vault: migrationParams.v2vault,
        migration: migrationParams.migration
      }, hre);
    });

    await withImpersonatedSigner(migrationOwner, async (migrationOwnerSigner) => {
      const emergencyExitTx = await migration.connect(migrationOwnerSigner).emergencyExit();
      await emergencyExitTx.wait();
    });

    await withImpersonatedSigner(treasury, async (treasurySigner) => {
      /// PERFORM TRANSFER OF TREASURY BALANCE TO DROPPER
      const balanceOfTreasury = await vault.balanceOf(treasury);
      const transferTx = await vault.connect(treasurySigner).transfer(dropper, balanceOfTreasury);
      await transferTx.wait();
    });

    await withImpersonatedSigner(dropperOwner, async (dropperOwnerSigner) => {
      await dropperContractInteractionActionBuilder(dropperOwnerSigner)({
        v2vault: migrationParams.v2vault,
        migration: migrationParams.migration,
        dropper: migrationParams.dropper,
        csv: migrationParams.csv
      }, hre);
    });
  });

  it('should perform final migration tasks successfully', async () => {
    const migrationParams = ethVaultMigrationParams;

    const vault = await ethers.getContractAt(
      "OnChainVault",
      migrationParams.v2vault
    );
    const dropper = await ethers.getContractAt(
      "Dropper",
      migrationParams.dropper
    );
    const migration = await ethers.getContractAt(
      "Migration",
      migrationParams.migration
    );

    const globalOwner = await vault.owner();
    const treasury = await migration.treasury();
    const dropperOwner = await dropper.owner();

    await mintNativeTokens(globalOwner, "0xF0000000000000000000000");
    await mintNativeTokens(treasury, "0xF0000000000000000000000");

    await withImpersonatedSigner(globalOwner, async (globalOwnerSigner) => {
      await migrationContractPopulationActionBuilder(globalOwnerSigner)({
        migration: migrationParams.migration,
        csvNonMigrated: migrationParams.csvNonMigrated,
        csvFinalMigration: migrationParams.csvFinalMigration
      }, hre);
    });

    await withImpersonatedSigner(globalOwner, async (globalOwnerSigner) => {
      await migrationContractInteractionActionBuilder(globalOwnerSigner)({
        v1vault: migrationParams.v1vault,
        v2vault: migrationParams.v2vault,
        migration: migrationParams.migration
      }, hre);
    });

    await withImpersonatedSigner(treasury, async (treasurySigner) => {
      /// PERFORM TRANSFER OF TREASURY BALANCE TO DROPPER
      const balanceOfTreasury = await vault.balanceOf(treasury);
      const transferTx = await vault.connect(treasurySigner).transfer(dropper, balanceOfTreasury);
      await transferTx.wait();
    });

    await withImpersonatedSigner(dropperOwner, async (dropperOwnerSigner) => {
      await additionalDropActionBuilder(dropperOwnerSigner)({
        migration: migrationParams.migration,
        v2vault: migrationParams.v2vault,
        csv: migrationParams.csvFinalMigration
      }, hre);
    });
  });
});
