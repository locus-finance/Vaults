const { ethers } = require("hardhat");

const migrationConfig = require("../../config/MigrationETH.json");

async function main() {
    const [signer] = await ethers.getSigners();
    const config = migrationConfig[hre.network.name];

    console.log("signer", signer.address);

    const dropper = await ethers.getContractAt(
        "Dropper",
      "0x7E1AEb6a32a9c30E6Ce393382417D6726a52b7E8"
    );

    const owner = await dropper.owner();
    console.log("Owner", owner);

    const dropTx = await dropper.connect(signer).drop(config.accounts, config.balances);
    const end = await dropTx.wait();

    console.log(end.cumulativeGasUsed);
    console.log(end.effectiveGasPrice);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
