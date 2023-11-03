const migrationContractPopulationActionBuilder = require('./reusable/migrationContractPopulation');
module.exports = (task) =>
  task(
    "populateMigration",
    "Populate Migration contract with non-migrated users.",
  )
    .addOptionalParam('migration', "Define from where the task should gather the drop receivers.", '0xC7469254416Ad546A5F07e5530a0c3eA468F1FCE', types.string)
    .addOptionalParam('csvNonMigrated', "Define a path with name for CSV file with non-migrated holders.", './tasks/migration/csv/postMigration/nonMigrated/lvAyiV1HoldersNonMigrated.csv', types.string)
    .addOptionalParam('csvFinalMigration', "Define a path with name for CSV file where will be finally migrated holders.", './tasks/migration/csv/postMigration/finalMigration/lvAyiV2HoldersFinallyMigrated.csv', types.string)
    .setAction(migrationContractPopulationActionBuilder());