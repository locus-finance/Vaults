const fsExtra = require('fs-extra');
const readAllFromDBService = require('./services/readAllService');
const parseHoldersAndBalances = require('../migration/reusable/parseHoldersAndBalances');

module.exports = (task) =>
  task(
    "generateFinalHoldersList",
    "Generates vaults holders list with validation in the DB.",
  )
    .addOptionalParam('result', "Define a path to where the validated CSV data would go.", './tasks/redeploy/csv/output/holdersLvETH-ETH-result.csv', types.string)
    .addOptionalParam('csv', "Define a path where CSV from vault token tracker exists.", './tasks/redeploy/csv/input/holdersLvETH-ETH.csv', types.string)
    .addOptionalParam('datetime', "Define a timestamp from which the database validator should start to select.", '2023-12-31T01:00:00.000Z', types.string)
    .addOptionalParam('decimals', "Define a decimals for balance formatting in the CSV table.", 18, types.int)
    .setAction(async ({ result, csv, datetime, decimals }, hre) => {
      const network = csv.split('-')[1].split('.')[0];
      console.log(`Using ${csv} table, network ${network}.`);
      const csvUsers = await parseHoldersAndBalances(
        "HolderAddress",
        "Balance",
        csv,
        balance => hre.ethers.utils.parseUnits(
          balance.includes(',')
            ? balance.replace(',', '')
            : balance,
          decimals
        ),
        hre.ethers.utils.getAddress
      );
      const usersAtTimestamp = await readAllFromDBService(network, datetime, decimals);

      const validatedUsers = [];

      console.log('Validation has been started...');
      
      for (const csvUser of csvUsers) {
        for (const userAtTimestamp of usersAtTimestamp) {
          if (csvUser.address === userAtTimestamp.user_addr) {
            console.log(csvUser.address, csvUser.balance.toString());
            console.log(userAtTimestamp.user_addr, userAtTimestamp.amount.toString());
            console.log(csvUser.address === userAtTimestamp.user_addr && csvUser.balance.gte(userAtTimestamp.amount));
            validatedUsers.push({
              address: csvUser.address,
              balance: csvUser.balance.gte(userAtTimestamp.amount) ? userAtTimestamp.amount : csvUser.balance
            });
          }
        }
      }
      console.log('Gathered validated users. Composing resulting table...');

      let csvString = "\"receiver\",\"balance\"\n";
      await fsExtra.ensureFile(result);
      for (let i = 0; i < validatedUsers.length; i++) {
        csvString += `${validatedUsers.address},${validatedUsers.balance}\n`;
      }
      await fsExtra.outputFile(result, csvString);
      console.log('Validation finished successfully.');

      console.log(csvUsers);
      console.log('**************************************');
      console.log(usersAtTimestamp.map(e => {
        return {address: e.user_addr, balance: e.amount};
      }));
      console.log('**************************************');
      console.log(validatedUsers);
    });