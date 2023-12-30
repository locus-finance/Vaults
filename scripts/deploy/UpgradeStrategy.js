const { ethers } = require("hardhat");

async function main() {
  console.log('Starting...');
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const strategyFactory = await ethers.getContractFactory("SaverStrategy");

  console.log('Constructed factory...');

  const vault = "0x0e86f93145d097090aCBBB8Ee44c716DACFf04d7";

  const strategy = await hre.upgrades.upgradeProxy(
    "0x9DFE70C850B3a7D098252c293AFf1162B27EEDC9",
    strategyFactory,
    [
      vault,
      "0x27f52fd2E60B1153CBD00D465F97C05245D22B82",
      "0x5C6412CE0E1f5C15C98AEbc5353d936Ed9bC5Bf1"
    ],
    {
      kind: "transparent",
      constructorArgs: [vault],
      unsafeAllow: ["constructor"]
    }
  );

  await hre.run("verify:verify", {
    address: strategy.address,
    constructorArguments: [vault],
  });

  console.log("Strategy address:", strategy.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });