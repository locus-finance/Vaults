const { ethers, upgrades } = require("hardhat");

module.exports = async function ({ getNamedAccounts }) {
  const { deployer } = await getNamedAccounts();

  console.log(`Your address: ${deployer}. Network: ${hre.network.name}`);

  const Vault = await ethers.getContractFactory("OnChainVault");
  const vault = await upgrades.deployProxy(
    Vault,
    [
      "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
      deployer,
      deployer,
      "DeFi Core Index",
      "lvDCI",
    ],
    {
      initializer: "initialize",
      kind: "transparent",
    }
  );
  await vault.deployed();

  console.log("Vault deployed to:", vault.address);

  await hre.run("verify:verify", {
    address: vault.address,
  });
};

module.exports.tags = ["OnChainVault_lvDCI"];
