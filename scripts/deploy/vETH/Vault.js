const hre = require("hardhat");

const { getEnv } = require("../../utils");

const WETH_DECIMALS = 18;
const WETH_ADDRESS = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";

const DEPLOY_SETTINGS = {
    want: WETH_ADDRESS,
    name: "vETHVault",
    symbol: "vETH",
    governance: getEnv("GOVERNANCE_ACCOUNT"),
    treasury: getEnv("TREASURY_ACCOUNT"),
    depositLimitWeth: "1000",
    performanceFee: 500,
    managementFee: 70,
};

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    const {
        want,
        name,
        symbol,
        governance,
        treasury,
        depositLimitWeth,
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
        ethers.utils.parseUnits(depositLimitWeth, WETH_DECIMALS)
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
