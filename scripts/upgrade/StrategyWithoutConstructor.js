const { getEnv } = require("../utils");

const TARGET_STRATEGY = getEnv("TARGET_STRATEGY");
const TARGET_ADDRESS = getEnv("TARGET_ADDRESS");

async function main() {
  const upgradeSettings = {
    UsdcUsdyStrategy: {
        libraryNames: ["UsdcUsdyStrategyLib"]
    },
    LendWmntStrategy: {
        libraryNames: ["LendWmntStrategyLib"]
    },
    MoeWmntStrategy: {
        libraryNames: ["MoeWmntStrategyLib"]
    },
    MethWethStrategy: {
        libraryNames: ["MethWethStrategyLib"]
    },
    WmntMethStrategy: {
        libraryNames: ["WmntMethStrategyLib"]
    }
};
  let TargetContract;
  if (upgradeSettings[TARGET_STRATEGY].libraryNames !== undefined) {
    const libraries = {};
    console.log('Found libraries to deploy and link!');
    for (const libraryName of upgradeSettings[TARGET_STRATEGY].libraryNames) {
        const library = await hre.ethers.deployContract(libraryName);
        console.log(`Deployed library: ${libraryName} - ${library.address}`);
        libraries[libraryName] = library.address;
        await hre.run("verify:verify", {
          address: library.address
      });
    }
    TargetContract = await hre.ethers.getContractFactory(TARGET_STRATEGY, {libraries});
  } else {
    console.log("No external libraries for this strategy. Continue...");
    TargetContract = await hre.ethers.getContractFactory(TARGET_STRATEGY);
  }
  console.log("Preparing upgrade...");

  console.log(
    "Implementation address: " +
      (await hre.upgrades.erc1967.getImplementationAddress(TARGET_ADDRESS))
  );
  const adminAddr = await hre.upgrades.erc1967.getAdminAddress(TARGET_ADDRESS);
  console.log("Admin address: " + adminAddr);

  const upgraded = await hre.upgrades.upgradeProxy(
    TARGET_ADDRESS,
    TargetContract,
    {
      unsafeAllow: ["external-library-linking"]
    }
  );

  console.log("Successfully upgraded implementation of", upgraded.address);
  console.log(
    "New implementation address: " +
      (await hre.upgrades.erc1967.getImplementationAddress(TARGET_ADDRESS))
  );

  await hre.run("verify:verify", {
    address: upgraded.address
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
