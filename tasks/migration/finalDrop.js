const additionalDropActionBuilder = require('./reusable/additionalDrop');
module.exports = (task) =>
  task(
    "finalDrop",
    "Drop tokens on Dropper to Vaults V2.",
  )
    .addOptionalParam('v2vault', "Define to where the migration should occur.", '0x0f094f6deb056af1fa1299168188fd8c78542a07', types.string)
    .addOptionalParam('dropper', "Define from where the task should gather the drop receivers.", '0xEB20d24d42110B586B3bc433E331Fe7CC32D1471', types.string)
    .addOptionalParam('csv', "Define a full path with name for CSV file.", './tasks/migration/csv/postMigration/finalMigration/lvAyiV2HoldersFinallyMigrated.csv', types.string)
    .setAction(additionalDropActionBuilder());