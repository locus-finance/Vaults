const { ethers } = require("hardhat");

module.exports = async function ({ getNamedAccounts }) {
  const { deployer } = await getNamedAccounts();

  console.log(`Your address: ${deployer}. Network: ${hre.network.name}`);
  const vault = "0xBE55f53aD3B48B3ca785299f763d39e8a12B1f98";
  const treasury = "0xf4bec3e032590347fc36ad40152c7155f8361d39";
  const Dropper = await ethers.getContractFactory("Dropper");
  const dropper = await Dropper.deploy(
    vault,
    treasury
  );
  await dropper.deployed();

  console.log("Dropper deployed to:", dropper.address);

  await hre.run("verify:verify", {
    address: dropper.address,
    constructorArguments: [vault, treasury],});
};

module.exports.tags = ["Dropper"];
