const migrationContractPopulationActionBuilder = require('./reusable/migrationContractPopulation');
module.exports = (task) =>
  task(
    "populateMigration",
    "Populate Migration contract with non-migrated users.",
  )
    .addOptionalParam('migration', "Define from where the task should gather the drop receivers.", '0xf42402303BCA9d5575A8aC7b90CB18026c80354D', types.string)
    .addOptionalParam('csvNonMigrated', "Define a path with name for CSV file with non-migrated holders.", './tasks/migration/csv/postMigration/nonMigrated/lvEthV1HoldersNonMigrated.csv', types.string)
    .addOptionalParam('csvFinalMigration', "Define a path with name for CSV file where will be finally migrated holders.", './tasks/migration/csv/postMigration/finalMigration/lvEthV2HoldersFinallyMigrated.csv', types.string)
    .setAction(migrationContractPopulationActionBuilder());