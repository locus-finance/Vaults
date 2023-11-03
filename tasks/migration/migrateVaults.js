const migrationContractInteractionActionBuilder = require('./reusable/steps/migrationContractInteraction');
module.exports = (task) =>
  task(
    "migrateVaults",
    "Migrate funds from Vault V1 to Vault V2.",
  )
    .addOptionalParam('v1vault', "Define from where the migration should occur.", '0xBE55f53aD3B48B3ca785299f763d39e8a12B1f98', types.string)
    .addOptionalParam('v2vault', "Define to where the migration should occur.", '0x0f094f6deb056af1fa1299168188fd8c78542a07', types.string)
    .addOptionalParam('migration', "Define from where the task should gather the drop receivers.", '0xC7469254416Ad546A5F07e5530a0c3eA468F1FCE', types.string)
    .setAction(migrationContractInteractionActionBuilder());