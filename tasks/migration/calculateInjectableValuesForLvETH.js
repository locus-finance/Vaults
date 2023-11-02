const calculateInjectableValues = require('./reusable/calculateInjectableValues');

module.exports = (task) => task(
  "calculateInjectableValuesForLvETH",
  "Calculates and returns injectable values for the lvETH vault.",
  async (taskArgs, hre) => {
    return await calculateInjectableValues(
      "0x3edbE670D03C4A71367dedA78E73EA4f8d68F2E4",
      parseInt(process.env.ETH_FORK_BLOCK)
    )();
  }
);