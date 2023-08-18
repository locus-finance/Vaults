const hre = require("hardhat");

const { getEnv } = require("../utils");

const TARGET_ADDRESS = getEnv("TARGET_ADDRESS");
const TARGET_STRATEGY = getEnv("TARGET_STRATEGY");

async function main() {

  const TargetContract = await hre.ethers.getContractFactory(TARGET_STRATEGY);
  const strategyAddress = TargetContract.attach(TARGET_ADDRESS);
  const vault = await strategyAddress.vault();

  console.log('Running deploy script');

  const strategy = await hre.ethers.getContractFactory(TARGET_STRATEGY);

  const [deployer] = await hre.ethers.getSigners();

  await hre.upgrades.forceImport(TARGET_ADDRESS, TargetContract, {
    kind: "transparent",
    constructorArgs: [vault],
    from: deployer,
  });

  const upgraded = await hre.upgrades.upgradeProxy(TARGET_ADDRESS, strategy,
    {
      unsafeAllow: ["constructor"],
      constructorArgs: [vault],
    });
  console.log("strategy upgraded with ", upgraded.address);

  console.log("Verifying strategy");
  const routImplAddress = await hre.upgrades.erc1967.getImplementationAddress(TARGET_ADDRESS.address);
  console.log("strategy implementation: ", routImplAddress);

    await hre.run("verify:verify", {
        address: upgraded.address,
        constructorArguments: [vault],
    });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
