// deploy vault's proxy and implementation
const hre = require("hardhat");

async function main() {
    const [owner] = await ethers.getSigners();

    const wETHToken = "0xee44150250aff3e6ac25539765f056edb7f85d7b";
    const governance = owner.address;
    const treasury = owner.address;
    const vaultName = "ETH Vault";
    const vaultSymbol = "vETH";

    const BaseVault = await hre.ethers.getContractFactory("BaseVault");
    const vault = await BaseVault.deploy();

    await vault.deployed();

    let tx = await vault['initialize(address,address,address,string,string)'](wETHToken, governance, treasury, vaultName, vaultSymbol);
    await tx.wait();

    console.log(
        `ETH vault deployed to ${vault.address}`
    );
    console.log("Contract symbol:", await vault.symbol());
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});