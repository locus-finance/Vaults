const { upgrades } = require("hardhat");
const { getEnv } = require("../utils");

const TARGET_ADDRESS = getEnv("TARGET_ADDRESS");

// in case you want to add and check specific addresses
const targets = [
  TARGET_ADDRESS
];

async function main() {
  for (const target of targets) {
    const adminAddr = await upgrades.erc1967.getAdminAddress(
      target
    );
    console.log(`Admin address of a ${target}: - ${adminAddr}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });

