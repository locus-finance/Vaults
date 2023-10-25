const {
    loadFixture,
  } = require("@nomicfoundation/hardhat-network-helpers");
  const { expect } = require("chai");
  const { utils } = require("ethers");
  const { ethers } = require("hardhat");
  
  const { getEnv } = require("../../scripts/utils");
  
  const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";
  
  const ETH_NODE_URL = getEnv("ETH_NODE");
  const ETH_FORK_BLOCK = getEnv("ETH_FORK_BLOCK");
  
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

      const migrationOwner = "0xAe7B63DAd95581947d2925A9e62E57CCbb2dA046";
      const vaultOwner = migrationOwner;
      
      await mintNativeTokens(migrationOwner, "0x10000000000000000000000");
      await withImpersonatedSigner(migrationOwner, async (migrationOwnerSigner) => {
        await migration.connect(migrationOwnerSigner).withdraw();
      });

      // await withImpersonatedSigner(vaultOwner, async (vaultOwnerSigner) => {
      //   const {totalSupplyToInject, freeFundsToInject} = await hre.run("calculateInjectableValuesForLvETH");
      //   await vault.connect(vaultOwnerSigner).injectForMigration(totalSupplyToInject, freeFundsToInject);
      // });

      await withImpersonatedSigner(migrationOwner, async (migrationOwnerSigner) => {
        await migration.connect(migrationOwnerSigner).deposit();
        await migration.connect(migrationOwnerSigner).emergencyExit();
      });

      await hre.run("executeDropLvETH");
    });
  });
  