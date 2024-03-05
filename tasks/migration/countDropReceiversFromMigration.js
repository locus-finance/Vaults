module.exports = (task) => 
  task(
    "countDropReceiversFromMigration",
    "Counts drop(...) operation receivers.",
  )
    .addOptionalParam('migration', "Define an address of Migration contract from where the task should gather info about drop receivers.", '0xd25d0de43579223429c28f2d64183a47a79078C7', types.string)
    .setAction(async ({ migration }, hre) => {
      const migrationInstance = await hre.ethers.getContractAt(
        "Migration",
        migration
      );
      let count = 0;
      for (count; count < 1000; count++) {
        try {
          await migrationInstance.users(count);
        } catch (_) {
          break;
        }
      }
      const result = count;
      console.log(`Length of migration users array is: ${result}`);
      return result;
    });