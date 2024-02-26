const { ethers } = require("hardhat");

module.exports = async function ({ getNamedAccounts }) {
  const { deployer } = await getNamedAccounts();

  console.log(`Your address: ${deployer}. Network: ${hre.network.name}`);
  const vaultV1 = "0xf62A24EbE766d0dA04C9e2aeeCd5E86Fac049B7B";
  const vaultV2 = "0xB0a66dD3B92293E5DC946B47922C6Ca9De464649";
  const simpleMigrationFactory = await ethers.getContractFactory("SimpleMigration");
  const simpleMigration = await simpleMigrationFactory.deploy(
    vaultV2,
    vaultV1
  );
  await simpleMigration.deployed();

  console.log("SimpleMigration deployed to:", simpleMigration.address);

  await hre.run("verify:verify", {
    address: simpleMigration.address,
    constructorArguments: [vaultV2, vaultV1],});
};

module.exports.tags = ["SimpleMigration"];
