const hre = require("hardhat");

const { getEnv } = require("../../utils");

const WETH_DECIMALS = 18;

const DEPLOY_SETTINGS = {
    vaultAddress: getEnv("VETH_ADDRESS"),
    ratio: "2100",
    minDebtHarvestWeth: "0",
    maxDebtHarvestWeth: "1000",
};

async function main() {
    const [deployer] = await ethers.getSigners();
    const { vaultAddress, ratio, minDebtHarvestWeth, maxDebtHarvestWeth } =
        DEPLOY_SETTINGS;

    const Vault = await hre.ethers.getContractFactory("Vault");
    const vault = Vault.attach(vaultAddress);

    const FraxStrategy = await hre.ethers.getContractFactory("FraxStrategy");
    const strategy = await FraxStrategy.deploy(vault.address);
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
        `Vault strategy indicators: ${await vault.strategies(strategy.address)}`
    );
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });