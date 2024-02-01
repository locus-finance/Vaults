// const hre = require("hardhat");
const { ethers, upgrades } = require("hardhat");

const { getEnv } = require("../utils");

const TARGET_VAULT = getEnv("TARGET_VAULT");
const TARGET_ADDRESS = getEnv("TARGET_ADDRESS");

async function main() {
  const TargetContract = await hre.ethers.getContractFactory(TARGET_VAULT);
  const vault = TargetContract.attach(TARGET_ADDRESS);
  console.log("Preparing upgrade...");

  console.log(
    "Implementation address: " +
      (await hre.upgrades.erc1967.getImplementationAddress(TARGET_ADDRESS))
  );
  const adminAddr = await hre.upgrades.erc1967.getAdminAddress(TARGET_ADDRESS);
  console.log("Admin address: " + adminAddr);

  const upgraded = await hre.upgrades.upgradeProxy(
    TARGET_ADDRESS,
    TargetContract
  );

  console.log("Successfully upgraded implementation of", upgraded.address);
  console.log(
    "New implementation address: " +
      (await hre.upgrades.erc1967.getImplementationAddress(TARGET_ADDRESS))
  );

  await hre.run("verify:verify", {
    address: upgraded.address  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
