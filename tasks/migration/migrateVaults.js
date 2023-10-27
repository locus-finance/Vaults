const migrationContractInteractionActionBuilder = require('./reusable/steps/migrationContractInteraction');
module.exports = (task) =>
  task(
    "migrateVaults",
    "Migrate funds from Vault V1 to Vault V2.",
  )
    .addOptionalParam('v1vault', "Define from where the migration should occur.", '0x3edbE670D03C4A71367dedA78E73EA4f8d68F2E4', types.string)
    .addOptionalParam('v2vault', "Define to where the migration should occur.", '0x0e86f93145d097090acbbb8ee44c716dacff04d7', types.string)
    .addOptionalParam('migration', "Define from where the task should gather the drop receivers.", '0xd25d0de43579223429c28f2d64183a47a79078C7', types.string)
    .setAction(migrationContractInteractionActionBuilder());