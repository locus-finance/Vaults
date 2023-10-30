const treasuryTransferActionBuilder = require('./reusable/steps/treasuryTransfer');
module.exports = (task) =>
  task(
    "treasuryAction",
    "Send funds aggregated in treasury to Dropper contract.",
  )
    .addOptionalParam('v2vault', "Define to where the migration should occur.", '0x65b08FFA1C0E1679228936c0c85180871789E1d7', types.string)
    .addOptionalParam('dropper', "Define from where the task should gather the drop receivers.", '0xEB20d24d42110B586B3bc433E331Fe7CC32D1471', types.string)
    .addOptionalParam('migration', "Define from where the task should gather the drop receivers.", '0xf42402303BCA9d5575A8aC7b90CB18026c80354D', types.string)
    .setAction(treasuryTransferActionBuilder());