const fsExtra = require('fs-extra');
const parseHoldersAndBalances = require('../migration/reusable/parseHoldersAndBalances');

module.exports = (task) =>
  task(
    "calculateWantBalances",
    "Calculate balances of resulting CSVs in want tokens.",
  )
    .addOptionalParam('result', "Define a path where validated CSV of want tokens balances and respective addresses would be stored.", './tasks/redeploy/csv/output/converted/holdersLvDCI-ATH-result-want-tokens.csv', types.string)
    .addOptionalParam('csv', "Define a path where validated CSV of balances and addresses are stored.", './tasks/redeploy/csv/output/validated/holdersLvDCI-ETH-result-vault-tokens.csv', types.string)
    .addOptionalParam('pps', "Define a PPS float value for conversion.", 0.904694, types.float)
    .addOptionalParam('decimals', "Define a decimals for balance formatting in the CSV table.", 6, types.int)
    .setAction(async ({ result, pps, csv, decimals }, hre) => {

      // sum of want tokens for LvDCI: 318479.391275199
      // sum of want tokens pre hack on LvDCI: 318242.20357

      console.log(`Using ${csv} table, PPS: ${pps}`);
      const csvUsers = await parseHoldersAndBalances(
        "receiver",
        "balance",
        csv
      );

      const convertedUsers = [];
      let sumOfWantTokens = 0;

      for (const user of csvUsers) {
        if (user.balance.eq(0)) continue;
        const amountOfWantTokens = hre.ethers.utils.formatUnits(user.balance, decimals) * pps; 
        convertedUsers.push({
          address: user.address,
          balance: amountOfWantTokens
        });
        sumOfWantTokens += amountOfWantTokens;
      }

      let csvString = "\"receiver\",\"balance\"\n";
      await fsExtra.ensureFile(result);
      for (let i = 0; i < convertedUsers.length; i++) {
        csvString += `${convertedUsers[i].address},${convertedUsers[i].balance}\n`;
      }
      await fsExtra.outputFile(result, csvString);
      console.log('Conversion finished successfully.');
      console.log(`Sum of want tokens: ${sumOfWantTokens}`);
    });