const executeDrop = require('../executeDrop');

module.exports = (customSigner) =>
  async (taskParams, hre) => {
    const { v2vault, migration, dropper, csv } = taskParams;

    const maxAmountOfUsers = await hre.run("countDropReceiversFromMigration", {
      migration
    });

    await hre.run('saveDropReceiversFromMigration', {
      migration,
      csv,
      count: maxAmountOfUsers
    });

    await executeDrop(
      'receiver',
      'balance',
      csv,
      v2vault,
      dropper,
      customSigner
    )();
  };