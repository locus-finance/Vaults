const { ethers, upgrades } = require("hardhat");

async function main() {
  
  const { deployer } = await getNamedAccounts();

  console.log(`Your address: ${deployer}. Network: ${hre.network.name}`);
  const treasury = "0xf4bEC3e032590347Fc36AD40152C7155f8361d39"
  const strategist = "0x942f39555D430eFB3230dD9e5b86939EFf185f0A"

  const Vault = await ethers.getContractFactory("OnChainVault");
  const vault = await upgrades.deployProxy(
    Vault,
    [
      "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
      strategist,
      treasury,
      "Locus Yield ETH",
      "xETH",
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

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });