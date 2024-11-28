const executeDrop = require('./executeDrop');

module.exports = (customSigner) =>
  async (taskParams, hre) => {
    const { v2vault, dropper, csv } = taskParams;
    await executeDrop(
      'receiver',
      'balance',
      csv,
      v2vault,
      dropper,
      customSigner
    )();
  };