const fsExtra = require('fs-extra');

module.exports = (task) => 
  task(
    "saveDropReceiversFromMigration",
    "Saves into CSV file drop(...) operation receivers.",
  )
    .addOptionalParam('migration', "Define from where the task should gather the drop receivers.", '0xd25d0de43579223429c28f2d64183a47a79078C7', types.string)
    .addOptionalParam('csv', "Define a relative path for CSV file.", './tasks/migration/csv/lvEthV2TokenReceiversReadyForDrop.csv', types.string)
    .addOptionalParam('count', "Define a max users count to be retrieved (cause there is no length measuring function in the current implementation).", 77, types.int)
    .setAction(async ({ migration, csv, count }, hre) => {
      const migrationInstance = await hre.ethers.getContractAt(
        "Migration",
        migration
      );
      let csvString = "\"receiver\",\"balance\"\n";
      await fsExtra.ensureFile(csv);
      for (let i = 0; i < count; i++) {
        const userAddress = await migrationInstance.users(i);
        const userBalance = (await migrationInstance.userToBalance(userAddress)).toString();
        csvString += `${userAddress},${userBalance}\n`;
      }
      await fsExtra.outputFile(csv, csvString);
      console.log(`Saved users and their balances from ${migration} to ${csv}`);
    });