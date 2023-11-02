const executeDrop = require('./reusable/executeDrop');

module.exports = (task) => task(
  "executeDropLvETH",
  "Executes drop(...) operation for lvETH vault.",
  async (taskArgs, hre) => {
    await executeDrop(
      'receiver', 
      'balance',
      "./tasks/migration/csv/lvEthV2TokenReceiversReadyForDrop.csv",
      "0x0e86f93145d097090acbbb8ee44c716dacff04d7",
      "0xEB20d24d42110B586B3bc433E331Fe7CC32D1471"
    )();
  }
);