const executeDrop = require('./reusable/executeDrop');

module.exports = (task) => task(
  "executeDropLvDCI",
  "Executes drop(...) operation for lvDCI vault.",
  async (taskArgs, hre) => {
    await executeDrop(
      'receiver', 
      'balance',
      "./tasks/migration/csv/lvDciV2TokenReceiversReadyForDrop.csv",
      "0x65b08FFA1C0E1679228936c0c85180871789E1d7",
      "0xEB20d24d42110B586B3bc433E331Fe7CC32D1471"
    )();
  }
);