const hre = require("hardhat");

const { getEnv } = require("../utils");

const TARGET_STRATEGY = getEnv("TARGET_STRATEGY");
const TARGET_ADDRESS = getEnv("TARGET_ADDRESS");

async function main() {
    const TargetContract = await ethers.getContractFactory(TARGET_STRATEGY);
    const strategy = TargetContract.attach(TARGET_ADDRESS);
    const vault = await strategy.vault();

    const upgraded = await hre.upgrades.upgradeProxy(
        TARGET_ADDRESS,
        TargetContract,
        {
            unsafeAllow: ["constructor"],
            constructorArgs: [vault],
        }
    );

    console.log(`Successfully upgraded implementation of ${TARGET_STRATEGY}`);

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
