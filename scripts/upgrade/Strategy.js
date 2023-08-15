const hre = require("hardhat");

const { getEnv } = require("../utils");

//const TARGET_STRATEGY = getEnv("TARGET_STRATEGY");
const TARGET_ADDRESS = getEnv("TARGET_ADDRESS");

async function main() {

  console.log('Running deploy script');
  const TargetContract = await hre.ethers.getContractFactory("FXSStrategy");
  const strategy = TargetContract.attach(TARGET_ADDRESS);
  const vault = await strategy.vault();
  console.log("Preparing upgrade...");

  console.log('Implementation address: ' + await hre.upgrades.erc1967.getImplementationAddress(TARGET_ADDRESS));
  console.log('Admin address: ' + await hre.upgrades.erc1967.getAdminAddress(TARGET_ADDRESS));

  const [deployer] = await hre.ethers.getSigners();
  await hre.upgrades.forceImport(TARGET_ADDRESS, TargetContract, {
    kind: "transparent",
    constructorArgs: [vault],
    from: deployer,
  });

    const upgraded = await hre.upgrades.upgradeProxy(
        TARGET_ADDRESS,
        TargetContract,
        {
            unsafeAllow: ["constructor"],
            constructorArgs: [vault],
        }
    );


    console.log("Successfully upgraded implementation of", upgraded.address);

    await hre.run("verify:verify", {
        address: upgraded.address,
        constructorArguments: [vault],
    });
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
