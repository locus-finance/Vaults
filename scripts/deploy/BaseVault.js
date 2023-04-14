// deploy vault's proxy and implementation
const hre = require("hardhat");
const prompt = require('prompt-sync')();

async function main() {
    const [owner] = await ethers.getSigners();

    const want = prompt('Vault want token address: ') || "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";

    // const want = "0xee44150250aff3e6ac25539765f056edb7f85d7b";
    const governance = owner.address;
    const treasury = owner.address;
    const vaultName = "ETH Vault";
    const vaultSymbol = "vETH";

    const BaseVault = await hre.ethers.getContractFactory("BaseVault");
    const vault = await BaseVault.deploy();

    await vault.deployed();

    let tx = await vault['initialize(address,address,address,string,string)'](want, governance, treasury, vaultName, vaultSymbol);
    await tx.wait();

    console.log(
        `ETH vault deployed to ${vault.address}`
    );
    console.log("Contract symbol:", await vault.symbol());
}

main()
.then(() => process.exit(0))
.catch((error) => {
    console.error(error);
    process.exitCode = 1;
});