const { ethers } = require("hardhat");
const { getEnv } = require("../utils");

const TARGET_STRATEGY = getEnv("TARGET_STRATEGY");

async function main() {
    const [signer] = await ethers.getSigners();
    console.log("signer", signer.address);

    const strategy = await ethers.getContractAt(
        "BaseStrategy",
        TARGET_STRATEGY
    );

    const strategist = await strategy.strategist();
    console.log("Strategist", strategist);

    const harvestTx = await strategy.connect(signer).harvest();
    const end = await harvestTx.wait();

    console.log(end.cumulativeGasUsed);
    console.log(end.effectiveGasPrice);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
