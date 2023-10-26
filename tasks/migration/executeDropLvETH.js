const executeDrop = require('./reusable/executeDrop');

module.exports = (task) => task(
  "executeDropLvETH",
  "Executes drop(...) operation for lvETH vault.",
  async (taskArgs, hre) => {
    await executeDrop(
      "./tasks/migration/csv/lvEthTokenHolders.csv",
      "0x3edbE670D03C4A71367dedA78E73EA4f8d68F2E4"
    )();
  }
);