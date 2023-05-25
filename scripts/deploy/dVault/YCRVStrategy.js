const hre = require("hardhat");

const { getEnv } = require("../../utils");

const USDC_DECIMALS = 6;

const DEPLOY_SETTINGS = {
    vaultAddress: getEnv("DVAULT_ADDRESS"),
    ratio: "10000",
    minDebtHarvestUsdc: "0",
    maxDebtHarvestUsdc: "100000",
};

async function main() {
    const [deployer] = await ethers.getSigners();
    const { vaultAddress, ratio, minDebtHarvestUsdc, maxDebtHarvestUsdc } =
        DEPLOY_SETTINGS;

    const Vault = await hre.ethers.getContractFactory("Vault");
    const vault = Vault.attach(vaultAddress);

    const YCRVStrategy = await hre.ethers.getContractFactory("YCRVStrategy");
    const strategy = await YCRVStrategy.deploy(vault.address);
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
        `Vault strategy indicators: ${await vault.strategies(strategy.address)}`
    );
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
