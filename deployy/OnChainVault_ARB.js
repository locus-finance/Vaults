const { ethers, upgrades } = require("hardhat");

module.exports = async function ({ getNamedAccounts }) {
  const { deployer } = await getNamedAccounts();

  console.log(`Your address: ${deployer}. Network: ${hre.network.name}`);

  const Vault = await ethers.getContractFactory("OnChainVault");
  const vault = await upgrades.deployProxy(
    Vault,
    [
      "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
      deployer,
      deployer,
      "Arbitrum Yield Index",
      "lvAYI",
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

module.exports.tags = ["OnChainVault_ARB"];
