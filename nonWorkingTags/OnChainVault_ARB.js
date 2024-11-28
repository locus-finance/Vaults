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
      "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
      strategist,
      treasury,
      "Arbitrum Yield Index",
      "xARB",
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