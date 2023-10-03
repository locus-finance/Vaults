// const hre = require("hardhat");
const { ethers, upgrades } = require('hardhat');

const { getEnv } = require("../utils");

const TARGET_STRATEGY = getEnv("TARGET_STRATEGY");
const TARGET_ADDRESS = getEnv("TARGET_ADDRESS");

async function main() {

    const TargetContract = await hre.ethers.getContractFactory(TARGET_STRATEGY);
    const strategy = TargetContract.attach(TARGET_ADDRESS);
    const vault = await strategy.vault();
    console.log("Preparing upgrade...");

    console.log(
        "Implementation address: " +
            (await hre.upgrades.erc1967.getImplementationAddress(
                TARGET_ADDRESS
            ))
    );
    const adminAddr = await hre.upgrades.erc1967.getAdminAddress(
        TARGET_ADDRESS
    );
    console.log("Admin address: " + adminAddr);

    const upgraded = await hre.upgrades.upgradeProxy(
        TARGET_ADDRESS,
        TargetContract,
        {
            unsafeAllow: ["constructor"],
            constructorArgs: [vault],
        }
    );

    console.log("Successfully upgraded implementation of", upgraded.address);
    console.log(
        "New implementation address: " +
            (await hre.upgrades.erc1967.getImplementationAddress(
                TARGET_ADDRESS
            ))
    );

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
