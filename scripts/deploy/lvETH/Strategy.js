const hre = require("hardhat");

const { getEnv } = require("../../utils");

const WETH_DECIMALS = 18;
const TARGET_STRATEGY = getEnv("TARGET_STRATEGY");

const DEPLOY_SETTINGS = {
    vaultAddress: getEnv("VETH_ADDRESS"),
    RocketAuraStrategy: {
        ratio: "3200",
        minDebtHarvestWeth: "0",
        maxDebtHarvestWeth: "100000",
    },
    LidoAuraStrategy: {
        ratio: "4000",
        minDebtHarvestWeth: "0",
        maxDebtHarvestWeth: "100000",
    },
    FraxStrategy: {
        ratio: "2100",
        minDebtHarvestWeth: "0",
        maxDebtHarvestWeth: "100000",
    },
    AuraTriPoolStrategy: {
        ratio: "1000",
        minDebtHarvestWeth: "0",
        maxDebtHarvestWeth: "100000",
    },
};

async function main() {
    if (!DEPLOY_SETTINGS[TARGET_STRATEGY]) {
        throw new Error(`Invalid target strategy: ${TARGET_STRATEGY}`);
    }

    const [deployer] = await ethers.getSigners();

    const { vaultAddress } = DEPLOY_SETTINGS;
    const { ratio, minDebtHarvestWeth, maxDebtHarvestWeth } =
        DEPLOY_SETTINGS[TARGET_STRATEGY];

    const Vault = await hre.ethers.getContractFactory("Vault");
    const vault = Vault.attach(vaultAddress);

    const Strategy = await hre.ethers.getContractFactory(TARGET_STRATEGY);
    const strategy = await hre.upgrades.deployProxy(
        Strategy,
        [vault.address, deployer.address],
        {
            initializer: "initialize",
            kind: "uups",
            constructorArgs: [vault.address],
            unsafeAllow: ["constructor"],
        }
    );
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
        ethers.utils.parseUnits(minDebtHarvestWeth, WETH_DECIMALS),
        ethers.utils.parseUnits(maxDebtHarvestWeth, WETH_DECIMALS),
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
