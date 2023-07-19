const hre = require("hardhat");

const { getEnv } = require("../../utils");

const USDC_DECIMALS = 6;
const USDC_ADDRESS = "0xaf88d065e77c8cc2239327c5edb3a432268e5831";

const DEPLOY_SETTINGS = {
    want: USDC_ADDRESS,
    name: "Arbitrum Yield Index ",
    symbol: "lvAYI",
    governance: getEnv("GOVERNANCE_ACCOUNT"),
    treasury: getEnv("TREASURY_ACCOUNT"),
    depositLimitUsdc: "500000000000",
    performanceFee: 1500,
    managementFee: 200,
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
