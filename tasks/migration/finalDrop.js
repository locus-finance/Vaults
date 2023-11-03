const additionalDropActionBuilder = require('./reusable/additionalDrop');
module.exports = (task) =>
  task(
    "dropToVaults",
    "Drop tokens on Dropper to Vaults V2.",
  )
    .addOptionalParam('v2vault', "Define to where the migration should occur.", '0x65b08FFA1C0E1679228936c0c85180871789E1d7', types.string)
    .addOptionalParam('dropper', "Define from where the task should gather the drop receivers.", '0xEB20d24d42110B586B3bc433E331Fe7CC32D1471', types.string)
    .addOptionalParam('csv', "Define a full path with name for CSV file.", './tasks/migration/csv/postMigration/finalMigration/lvEthV2HoldersFinallyMigrated.csv', types.string)
    .setAction(additionalDropActionBuilder());