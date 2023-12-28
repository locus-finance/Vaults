const { ethers, upgrades } = require("hardhat");

module.exports = async function ({ getNamedAccounts }) {
  const { deployer } = await getNamedAccounts();

  console.log(`Your address: ${deployer}. Network: ${hre.network.name}`);

  const Vault = await ethers.getContractFactory("OnChainVault");
  const vault = await upgrades.deployProxy(
    Vault,
    [
      "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
      deployer,
      deployer,
      "Locus Yield ETH",
      "lvETH",
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

module.exports.tags = ["OnChainVault_lvETH"];
