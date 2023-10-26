const fsExtra = require('fs-extra');

module.exports = (task) => 
  task(
    "saveDropReceiversFromMigration",
    "Saves into CSV file drop(...) operation receivers.",
  )
    .addOptionalParam('migration', "Define from where the task should gather the drop receivers.", '0xd25d0de43579223429c28f2d64183a47a79078C7', types.string)
    .addOptionalParam('csv', "Define a name for CSV file.", 'lvEthV2TokenReceiversReadyForDrop.csv', types.string)
    .addOptionalParam('count', "Define a max users count to be retrieved (cause there is no length measuring function in the current implementation).", 77, types.int)
    .addOptionalParam('v1vault', "Define an address of a Vault V1 to acquire balances.", "0x3edbE670D03C4A71367dedA78E73EA4f8d68F2E4", types.string)
    .setAction(async ({ migration, csv, count, v1vault }, hre) => {
      const migrationInstance = await ethers.getContractAt(
        "Migration",
        migration
      );
      const vaultV1 = await ethers.getContractAt(
        "IERC20",
        v1vault
      );
      const file = `./tasks/migration/csv/${csv}`;
      let csvString = "\"receiver\",\"balance\"\n";
      await fsExtra.ensureFile(file);
      for (let i = 0; i < count; i++) {
        const userAddress = await migrationInstance.users(i);
        const userBalance = (await vaultV1.balanceOf(userAddress)).toString();
        if (userBalance === "0") continue;
        csvString += `${userAddress},${userBalance}\n`;
      }
      await fsExtra.outputFile(file, csvString);
      console.log(`Saved users and their balances from ${migration} to ${file}`);
    });