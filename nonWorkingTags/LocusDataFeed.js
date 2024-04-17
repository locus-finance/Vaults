const { ethers, upgrades } = require("hardhat");

async function main() {
  const { deployer } = await getNamedAccounts();

  console.log(`Your address: ${deployer}. Network: ${hre.network.name}`);

  const locusDataFeedFactory = await hre.ethers.getContractFactory("LocusDataFeed");
  const locusDataFeed = await locusDataFeedFactory.deploy();
  await locusDataFeed.deployed();

  console.log("LocusDataFeed deployed to:", locusDataFeed.address);

  await hre.run("verify:verify", {
    address: locusDataFeed.address,
  });
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });