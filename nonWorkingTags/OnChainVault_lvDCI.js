const { ethers, upgrades } = require("hardhat");

async function main() {
  const { deployer } = await getNamedAccounts();

  console.log(`Your address: ${deployer}. Network: ${hre.network.name}`);

  const treasury = "0xf4bEC3e032590347Fc36AD40152C7155f8361d39"
  const strategist = "0x942f39555D430eFB3230dD9e5b86939EFf185f0A"

  // const Vault = await ethers.getContractFactory("OnChainVault");
  // const vault = await upgrades.deployProxy(
  //   Vault,
  //   [
  //     "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
  //     strategist,
  //     treasury,
  //     "DeFi Core Index",
  //     "xDEFI",
  //   ],
  //   {
  //     initializer: "initialize",
  //     kind: "transparent",
  //   }
  // );
  // await vault.deployed();

  // console.log("Vault deployed to:", vault.address);

  await hre.run("verify:verify", {
    address: "0xB0a66dD3B92293E5DC946B47922C6Ca9De464649",
  });
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });