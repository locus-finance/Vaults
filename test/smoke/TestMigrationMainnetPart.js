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
  
  describe("TestMigrationMainnetPart", () => {
  
    it("should make perform migrations withdraw, inject, deposit, emergencyExit, drop (using fork with real lvETH Vault)", async function () {
      const oldVault = await ethers.getContractAt(
        "OnChainVault",
        "0x3edbE670D03C4A71367dedA78E73EA4f8d68F2E4"
      );
      // await vault.injectForMigration(totalSupplyToInject, freeFundsToInject);
      const dropper = await ethers.getContractAt(
        "Dropper",
        "0xEB20d24d42110B586B3bc433E331Fe7CC32D1471"
      );
    });
  });
  