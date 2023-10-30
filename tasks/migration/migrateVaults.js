const migrationContractInteractionActionBuilder = require('./reusable/steps/migrationContractInteraction');
module.exports = (task) =>
  task(
    "migrateVaults",
    "Migrate funds from Vault V1 to Vault V2.",
  )
    .addOptionalParam('v1vault', "Define from where the migration should occur.", '0xf62A24EbE766d0dA04C9e2aeeCd5E86Fac049B7B', types.string)
    .addOptionalParam('v2vault', "Define to where the migration should occur.", '0x65b08FFA1C0E1679228936c0c85180871789E1d7', types.string)
    .addOptionalParam('migration', "Define from where the task should gather the drop receivers.", '0xf42402303BCA9d5575A8aC7b90CB18026c80354D', types.string)
    .setAction(migrationContractInteractionActionBuilder());