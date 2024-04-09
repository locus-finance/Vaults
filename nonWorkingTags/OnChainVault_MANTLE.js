const { ethers, upgrades } = require("hardhat");

async function main() {
  const { deployer } = await getNamedAccounts();

  console.log(`Your address: ${deployer}. Network: ${hre.network.name}`);

  const mantleUSDC = "0x09Bc4E0D864854c6aFB6eB9A9cdF58aC190D0dF9";
  const treasury = "0xf4bEC3e032590347Fc36AD40152C7155f8361d39"
  const strategist = "0x3C2792d5Ea8f9C03e8E73738E9Ed157aeB4FeCBe"

  const Vault = await ethers.getContractFactory("OnChainVault");
  const vault = await upgrades.deployProxy(
    Vault,
    [
      mantleUSDC,
      strategist,
      treasury,
      "Mantle Vault",
      "xMANTLE",
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