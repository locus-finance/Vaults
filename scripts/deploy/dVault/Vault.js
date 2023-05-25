const hre = require("hardhat");

const USDC_ADDRESS = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";

const DEPLOY_SETTINGS = {
    want: USDC_ADDRESS,
    name: "Locus DeFi Vault",
    symbol: "DFV",
    governance: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
    treasury: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
};

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    const { want, name, symbol, governance, treasury } = DEPLOY_SETTINGS;

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
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
