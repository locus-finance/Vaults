const dropperContractInteractionActionBuilder = require('./reusable/steps/dropperContractInteraction');
module.exports = (task) =>
  task(
    "dropToVaults",
    "Drop tokens on Dropper to Vaults V2.",
  )
    .addOptionalParam('v2vault', "Define to where the migration should occur.", '0x0e86f93145d097090acbbb8ee44c716dacff04d7', types.string)
    .addOptionalParam('migration', "Define from where the task should gather the drop receivers.", '0xd25d0de43579223429c28f2d64183a47a79078C7', types.string)
    .addOptionalParam('dropper', "Define from where the task should gather the drop receivers.", '0xEB20d24d42110B586B3bc433E331Fe7CC32D1471', types.string)
    .addOptionalParam('csv', "Define a name for CSV file.", 'lvEthV2TokenReceiversReadyForDrop.csv', types.string)
    .setAction(dropperContractInteractionActionBuilder());