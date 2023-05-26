const hre = require("hardhat");

const { getEnv } = require("../utils");

const STRATEGY_ADDRESS = "0x0fB38bE7FfA498AF483DF6CDA1776EB4E750Db63";

async function main() {
    await hre.run("verify:verify", {
        address: STRATEGY_ADDRESS,
        constructorArguments: [getEnv("VETH_ADDRESS")],
    });
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
