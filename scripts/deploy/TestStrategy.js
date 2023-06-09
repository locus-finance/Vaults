const hre = require("hardhat");
const prompt = require('prompt-sync')();

async function main() {
    const [owner] = await ethers.getSigners();

    const vaultAddr = prompt('Vault address: ') || '0xd8647a1018b9b2edaaf3bdd3482621798ab4c2e4';
    const ratio = prompt('Debt ratio (10000 = 100%): ') || '1000';
    const minDebtHarvest = prompt('Minimal debt harvest (ether): ') || '0';
    const maxDebtHarvest = prompt('Maximum debt harvest (ether): ') || '10000';
    const Vault = await hre.ethers.getContractFactory("Vault");
    const vault = await Vault.attach(vaultAddr);

    console.log("Current account: ", owner.address);
    console.log("Vault gov account: ", await vault.governance());

    const TestStrategy = await hre.ethers.getContractFactory("TestStrategy");
    const strategy = await TestStrategy.deploy(vault.address);
    await strategy.deployed();
    console.log(
        `${await strategy.name()} strategy deployed to ${strategy.address}`
    );

    const addStrategyTx = await vault['addStrategy(address,uint256,uint256,uint256,uint256)'](
        strategy.address, 
        Number(ratio), 
        ethers.utils.parseEther(minDebtHarvest), 
        ethers.utils.parseEther(maxDebtHarvest), 
        0
    );
    await addStrategyTx.wait();
    console.log("Vault strategy indicators:", await vault.strategies(strategy.address));
}

main()
.then(() => process.exit(0))
.catch((error) => {
    console.error(error);
    process.exitCode = 1;
});