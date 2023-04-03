// deploy vault's proxy and implementation
const hre = require("hardhat");

async function main() {
    const [owner, otherAccount] = await ethers.getSigners();

    const wETHToken = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
    const governance = owner.address;
    const treasury = owner.address;
    const vaultName = "ETH Vault";
    const vaultSymbol = "vETH";

    const BaseVault = await hre.ethers.getContractFactory("BaseVault");
    const vault = await BaseVault.deploy();

    await vault.deployed();

    await vault['initialize(address,address,address,string,string)'](wETHToken, governance, treasury, vaultName, vaultSymbol);

    console.log(
        `ETH vault deployed to ${vault.address}`
    );
    console.log("Contract symbol:", await vault.symbol());
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});