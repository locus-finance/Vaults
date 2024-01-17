const fsExtra = require('fs-extra');
const readAllFromDBService = require('./services/readAllService');
const parseHoldersAndBalances = require('../migration/reusable/parseHoldersAndBalances');

module.exports = (task) =>
  task(
    "generateFinalHoldersList",
    "Generates vaults holders list with validation in the DB.",
  )
    .addOptionalParam('result', "Define a path to where the validated CSV data would go.", './tasks/redeploy/csv/output/holdersLyUSD-ARB-result.csv', types.string)
    .addOptionalParam('csv', "Define a path where CSV from vault token tracker exists. NAME MUST BE FORMATTED AS <name>-<network symbol>.csv", './tasks/redeploy/csv/input/holdersLyUSD-ARB.csv', types.string)
    .addOptionalParam('datetime', "Define a timestamp from which the database validator should start to select.", '2023-12-31T01:00:00.000Z', types.string)
    .addOptionalParam('decimals', "Define a decimals for balance formatting in the CSV table.", 6, types.int)
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

      const csvUsersDict = {};
      for (const csvUser of csvUsers) {
        csvUsersDict[csvUser.address] = csvUser.balance;
      }
      const usersAtTimestampDict = {};
      for (const userAtTimestamp of usersAtTimestamp) {
        usersAtTimestampDict[userAtTimestamp.user_addr] = userAtTimestamp.amount;
      }

      for (const csvUserAddress in csvUsersDict) {
        validatedUsers.push({
          address: csvUserAddress,
          balance: 
            usersAtTimestampDict[csvUserAddress] !== undefined 
              && csvUsersDict[csvUserAddress].gte(usersAtTimestampDict[csvUserAddress]) 
            ? usersAtTimestampDict[csvUserAddress] 
            : csvUsersDict[csvUserAddress]
        });
      }

      for (const userAtTimestampAddress in usersAtTimestampDict) {
        if (csvUsersDict[userAtTimestampAddress] === undefined) {
          console.log(`Found one not in token tracker list: ${userAtTimestampAddress}. Adding...`);
          validatedUsers.push({
            address: userAtTimestampAddress,
            balance: usersAtTimestampDict[userAtTimestampAddress]
          });
        }
      }

      console.log('Gathered validated users. Composing resulting table...');

      let csvString = "\"receiver\",\"balance\"\n";
      await fsExtra.ensureFile(result);
      for (let i = 0; i < validatedUsers.length; i++) {
        csvString += `${validatedUsers[i].address},${validatedUsers[i].balance}\n`;
      }
      await fsExtra.outputFile(result, csvString);
      console.log('Validation finished successfully.');
    });