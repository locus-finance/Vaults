const { ethers } = require("hardhat");

const migrationConfig = require("../../../vaultsV2/constants/Migration.json");

module.exports = async function ({ getNamedAccounts }) {
  const { deployer } = await getNamedAccounts();

  console.log(`Your address: ${deployer}. Network: ${hre.network.name}`);
  const config = migrationConfig[hre.network.name];
  const Migration = await ethers.getContractFactory("Migration");
  const migration = await Migration.deploy(
    config.vaultV1,
    config.accounts,
    config.treasury
  );
  await migration.deployed();

  console.log("Migration deployed to:", migration.address);

  await hre.run("verify:verify", {
    address: migration.address,
    constructorArguments: [config.vaultV1, config.accounts, config.treasury],
  });
};

module.exports.tags = ["Migration"];
