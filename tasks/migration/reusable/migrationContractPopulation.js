const fsExtra = require('fs-extra');

const parseHoldersAndBalances = require("./parseHoldersAndBalances");

module.exports = (customSigner) =>
  async (taskParams, hre) => {
    const { migration, csvNonMigrated, csvFinalMigration } = taskParams;

    const migrationInstance = await hre.ethers.getContractAt(
      "Migration",
      migration
    );

    // balance == allowanceToMigration
    // address == receiver
    const nonMigratedHoldersInfo = await parseHoldersAndBalances(
      "receiver",
      "allowanceToMigration",
      csvNonMigrated
    );

    let csvString = "\"receiver\",\"balance\"\n";
    await fsExtra.ensureFile(csvFinalMigration);
    for (const holderInfo of nonMigratedHoldersInfo) {
      if (holderInfo.balance.gt(0)) {
        if (customSigner !== undefined) {
          await migrationInstance.connect(customSigner).addUser(holderInfo.address);
        } else {
          await migrationInstance.addUser(holderInfo.address);
        }
        csvString += `${holderInfo.address},${holderInfo.balance.toString()}\n`;
      }
    }

    await fsExtra.outputFile(csvFinalMigration, csvString);
    console.log(`Saved users and their balances for final migration from ${migration} to ${csvFinalMigration}`);
  };