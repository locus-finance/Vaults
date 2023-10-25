const calculateInjectableValues = require('./reusable/calculateInjectableValues');

module.exports = (task) => task(
  "calculateInjectableValuesForLvDCI",
  "Calculates and returns injectable values for the lvDCI vault.",
  async (taskArgs, hre) => {
    return await calculateInjectableValues(
      "0xf62A24EbE766d0dA04C9e2aeeCd5E86Fac049B7B",
      parseInt(process.env.ETH_FORK_BLOCK)
    )();
  }
);
  