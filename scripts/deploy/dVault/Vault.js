const hre = require("hardhat");

const { getEnv } = require("../../utils");

const USDC_DECIMALS = 6;
const USDC_ADDRESS = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";

const DEPLOY_SETTINGS = {
    want: USDC_ADDRESS,
    name: "dVault",
    symbol: "dvToken",
    governance: getEnv("GOVERNANCE_ACCOUNT"),
    treasury: getEnv("TREASURY_ACCOUNT"),
    depositLimitUsdc: "1000000000",
    performanceFee: 1500,
    managementFee: 150,
};

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    const {
        want,
        name,
        symbol,
        governance,
        treasury,
        depositLimitUsdc,
        managementFee,
        performanceFee,
    } = DEPLOY_SETTINGS;

    const Vault = await hre.ethers.getContractFactory("Vault");
    const vault = await Vault.deploy();
    await vault.deployed();

    const tx = await vault["initialize(address,address,address,string,string)"](
        want,
        governance,
        treasury,
        name,
        symbol
    );
    await tx.wait();

    console.log(`${name} deployed to ${vault.address} by ${deployer.address}`);
    console.log(`Vault symbol: ${await vault.symbol()}`);

    const limitTx = await vault["setDepositLimit(uint256)"](
        ethers.utils.parseUnits(depositLimitUsdc, USDC_DECIMALS)
    );
    await limitTx.wait();
    console.log(`Set deposit limit to ${await vault.depositLimit()}`);

    const performanceFeeTx = await vault["setPerformanceFee(uint256)"](
        performanceFee
    );
    await performanceFeeTx.wait();
    console.log(`Set performance fee to ${await vault.performanceFee()}`);

    const managementFeeTx = await vault["setManagementFee(uint256)"](
        managementFee
    );
    await managementFeeTx.wait();
    console.log(`Set management fee to ${await vault.managementFee()}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
