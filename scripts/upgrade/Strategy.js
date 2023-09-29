// const hre = require("hardhat");
const { ethers, upgrades } = require('hardhat');

const { getEnv } = require("../utils");

const TARGET_ADDRESS = getEnv("TARGET_ADDRESS");
const TARGET_STRATEGY = getEnv("TARGET_STRATEGY");

async function main() {

  const TargetContract = await ethers.getContractFactory(TARGET_STRATEGY);
  const strategyAddress = TargetContract.attach(TARGET_ADDRESS);
  const vault = await strategyAddress.vault();

  console.log('Running deploy script');
  console.log(TARGET_STRATEGY)

  const strategy = await ethers.getContractFactory(TARGET_STRATEGY);

  console.log("Preparing upgrade...");

  // const strategy2 = await upgrades.prepareUpgrade(TARGET_ADDRESS, strategy);
  // console.log("strategy2", strategy2);
  const upgraded = await upgrades.upgradeProxy(TARGET_ADDRESS, strategy, { constructorArgs: [TARGET_ADDRESS] });
  console.log("strategy upgraded with ", upgraded.address);

  console.log("Verifying strategy");
  const routImplAddress = await upgrades.erc1967.getImplementationAddress(TARGET_ADDRESS.address);
  console.log("strategy implementation: ", routImplAddress);

  await hre.run("verify:verify", {
    address: upgraded.address,
    constructorArguments: [vault],
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
