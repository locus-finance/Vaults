const hre = require("hardhat");

const { getEnv } = require("../../utils");

const TARGET_STRATEGY = getEnv("TARGET_STRATEGY");

const strategist = "0xC1287e8e489e990b424299376f37c83CD39Bfc4c"


const DEPLOY_SETTINGS = {
    vaultAddress: getEnv("lvDCI_ADDRESS"),
    CVXStrategy: {
        ratio: "3000",
        minDebtHarvestUsdc: "0",
        maxDebtHarvestUsdc: "1000000000000",
    },
    FXSStrategy: {
        ratio: "2914",
        minDebtHarvestUsdc: "0",
        maxDebtHarvestUsdc: "1000000000000",
    },
    AuraBALStrategy: {
        ratio: "3000",
        minDebtHarvestUsdc: "0",
        maxDebtHarvestUsdc: "1000000000000",
    },
    AuraWETHStrategy: {
        ratio: "3000",
        minDebtHarvestUsdc: "0",
        maxDebtHarvestUsdc: "1000000000000",
    },
};
const OWNABLE_ABI = ["function owner() view returns (address)"];

async function main() {
    if (!DEPLOY_SETTINGS[TARGET_STRATEGY]) {
        throw new Error(`Invalid target strategy: ${TARGET_STRATEGY}`);
    }

    const [deployer] = await ethers.getSigners();

    const { vaultAddress } = DEPLOY_SETTINGS;

    const Vault = await hre.ethers.getContractFactory("OnChainVault");
    const vault = Vault.attach(vaultAddress);

    const Strategy = await hre.ethers.getContractFactory(
        TARGET_STRATEGY,
        deployer
    );
    const strategy = await upgrades.deployProxy(
        Strategy,
        [vault.address, strategist],
        {
            initializer: "initialize",
            kind: "transparent",
            constructorArgs: [vault.address],
            unsafeAllow: ["constructor"],
        }
    );
    await strategy.deployed();

    const adminAddr = await hre.upgrades.erc1967.getAdminAddress(
        strategy.address
    );
    const ownableContract = await hre.ethers.getContractAt(
        OWNABLE_ABI,
        adminAddr
    );

    console.log(
        `${await strategy.name()} strategy deployed to ${strategy.address} by ${
            deployer.address
        }\n`
    );
    console.log(`Strategy proxyAdmin address: ${adminAddr}\n`);
    console.log(`proxyAdmin owner: ${await ownableContract.owner()}\n`);

    try {
        const { ratio, minDebtHarvestUsdc, maxDebtHarvestUsdc } =
            DEPLOY_SETTINGS[TARGET_STRATEGY];
        const addStrategyTx = await vault[
            "addStrategy(address,uint256,uint256,uint256,uint256)"
        ](
            strategy.address,
            Number(ratio),
            500,
            minDebtHarvestUsdc,
            maxDebtHarvestUsdc,
        );
        await addStrategyTx.wait();

        console.log(
            "Vault strategy indicators:",
            await vault.strategies(strategy.address)
        );
    } catch (e) {
        console.log(`Failed to add strategy to vault: ${e}`);
    }

    await hre.run("verify:verify", {
        address: strategy.address,
        constructorArguments: [vault.address],
    });
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
