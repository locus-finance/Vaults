const hre = require("hardhat");

const { getEnv } = require("../../utils");

const USDC_DECIMALS = 6;
const TARGET_STRATEGY = getEnv("TARGET_STRATEGY");

const DEPLOY_SETTINGS = {
    vaultAddress: getEnv("DAVAULT_ADDRESS"),
    YCRVStrategy: {
        ratio: "2000",
        minDebtHarvestUsdc: "0",
        maxDebtHarvestUsdc: "1000000",
    },
    CVXStrategy: {
        ratio: "2400",
        minDebtHarvestUsdc: "0",
        maxDebtHarvestUsdc: "10000000",
    },
    FXSStrategy: {
        ratio: "2200",
        minDebtHarvestUsdc: "0",
        maxDebtHarvestUsdc: "1000000",
    },
    AuraBALStrategy: {
        ratio: "1500",
        minDebtHarvestUsdc: "0",
        maxDebtHarvestUsdc: "1000000",
    },
    AuraWETHStrategy: {
        ratio: "1900",
        minDebtHarvestUsdc: "0",
        maxDebtHarvestUsdc: "1000000",
    },
};

async function main() {
    if (!DEPLOY_SETTINGS[TARGET_STRATEGY]) {
        throw new Error(`Invalid target strategy: ${TARGET_STRATEGY}`);
    }

    const [deployer] = await ethers.getSigners();

    const { vaultAddress } = DEPLOY_SETTINGS;
    const { ratio, minDebtHarvestUsdc, maxDebtHarvestUsdc } =
        DEPLOY_SETTINGS[TARGET_STRATEGY];

    const Vault = await hre.ethers.getContractFactory("Vault");
    const vault = Vault.attach(vaultAddress);

    const Strategy = await hre.ethers.getContractFactory(TARGET_STRATEGY);
    const strategy = await Strategy.deploy(vault.address);
    await strategy.deployed();

    console.log(
        `${await strategy.name()} strategy deployed to ${strategy.address} by ${
            deployer.address
        }\n`
    );

    const addStrategyTx = await vault[
        "addStrategy(address,uint256,uint256,uint256,uint256)"
    ](
        strategy.address,
        Number(ratio),
        ethers.utils.parseUnits(minDebtHarvestUsdc, USDC_DECIMALS),
        ethers.utils.parseUnits(maxDebtHarvestUsdc, USDC_DECIMALS),
        0
    );
    await addStrategyTx.wait();

    console.log(
        "Vault strategy indicators:",
        await vault.strategies(strategy.address)
    );

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
