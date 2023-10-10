const hre = require("hardhat");

const { getEnv } = require("../utils");

// const TARGET_ADDRESS = getEnv("TARGET_ADDRESS");
// const TARGET_STRATEGY = getEnv("TARGET_STRATEGY");

const abi = ["function balanceOf(address account) external view returns (uint256)"]

async function main() {

    const TargetContract = await ethers.getContractAt(abi, "0x7EA2be2df7BA6E54B1A9C70676f668455E329d29");
    console.log(await TargetContract.balanceOf("0x5E583B6a1686f7Bc09A6bBa66E852A7C80d36F00"))


}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
