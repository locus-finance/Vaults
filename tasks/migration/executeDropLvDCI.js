const executeDrop = require('./reusable/executeDrop');

module.exports = (task) => task(
  "executeDropLvDCI",
  "Executes drop(...) operation for lvDCI vault.",
  async (taskArgs, hre) => {
    await executeDrop(
      "./tasks/migration/csv/lvDciTokenHolders.csv",
      "0xf62A24EbE766d0dA04C9e2aeeCd5E86Fac049B7B"
    )();
  }
);