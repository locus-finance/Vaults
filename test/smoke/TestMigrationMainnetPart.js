const { ethers } = require("hardhat");
const executeDrop = require('../../tasks/migration/reusable/executeDrop');

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
  it("should make perform migrations withdraw, inject, deposit, emergencyExit, drop (using fork with real lvETH Vault)", async function () {
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
        if ((await vault.depositLimit()).eq(0)) {
          await vault.connect(vaultOwnerSigner).setDepositLimit(ethers.constants.MaxUint256);
        }
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

    console.log((await vault.balanceOf(dropper.address)).toString());
    
    await withImpersonatedSigner(droppedOwner, async (droppedOwnerSigner) => {
      await executeDrop(
        "./tasks/migration/csv/lvEthTokenHolders.csv",
        "0x3edbE670D03C4A71367dedA78E73EA4f8d68F2E4",
        droppedOwnerSigner
      )();
    });
  });
});
