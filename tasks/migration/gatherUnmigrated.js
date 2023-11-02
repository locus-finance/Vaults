const parseHoldersAndBalances = require('./reusable/parseHoldersAndBalances');
const fsExtra = require('fs-extra');

module.exports = (task) =>
  task(
    "gatherUnmigrated",
    "Saves into CSV file addresses and approves of unmigrated fellows.",
  )
    .addOptionalParam('v1vault', "Define from where the migration should occur.", '0xBE55f53aD3B48B3ca785299f763d39e8a12B1f98', types.string)
    .addOptionalParam('migration', "Define from where the task should gather the drop receivers.", '0xC7469254416Ad546A5F07e5530a0c3eA468F1FCE', types.string)
    .addOptionalParam('csvIn', "Define a relative path for CSV file of holders.", './tasks/migration/csv/postMigration/lvAyiV1HoldersPostMigration.csv', types.string)
    .addOptionalParam('csvOut', "Define a relative path for CSV file output information: holder - migration status.", './tasks/migration/csv/postMigration/nonMigrated/lvAyiV1HoldersNonMigrated.csv', types.string)
    .setAction(async ({ migration, v1vault, csvOut, csvIn }, hre) => {
      const migrationInstance = await hre.ethers.getContractAt(
        "Migration",
        migration
      );
      const v1vaultInstance = await hre.ethers.getContractAt(
        "IERC20",
        v1vault
      );

      let csvString = "\"receiver\",\"v1Balance\",\"allowanceToMigration\",\"includedInMigration\",\"registeredBalanceInMigration\"\n";

      await fsExtra.ensureFile(csvOut);

      const maxAmountOfUsers = await hre.run("countDropReceiversFromMigration", {
        migration
      });

      const isAddressIncludedInMigration = async (address) => {
        let result;
        for (let i = 0; i < maxAmountOfUsers; i++) {
          const userAddress = await migrationInstance.users(i);
          if (address === userAddress) {
            result = {
              inlcuded: true,
              registeredBalance: (await migrationInstance.userToBalance(userAddress)).toString()
            };
            console.log(result);
            return result;
          }
        }
        result = {
          included: false,
          registeredBalance: hre.ethers.constants.Zero
        };
        console.log(result);
        return result;
      }

      const parsedHolders = await parseHoldersAndBalances(
        "HolderAddress", 
        "Balance", 
        csvIn,
        (rawBalance) => rawBalance.includes(",")
          ? hre.ethers.utils.parseEther(rawBalance.replace(",", ""))
          : hre.ethers.utils.parseEther(rawBalance)
      );
      
      for (const parsedHolder of parsedHolders) {
        const allowance = await v1vaultInstance.allowance(parsedHolder.address, migrationInstance.address);
        const isAddressIncludedInfo = await isAddressIncludedInMigration(parsedHolder.address);     
        csvString += `${parsedHolder.address},${hre.ethers.utils.formatUnits(parsedHolder.balance)},${hre.ethers.utils.formatUnits(allowance.toString())},${isAddressIncludedInfo.included},${hre.ethers.utils.formatUnits(isAddressIncludedInfo.registeredBalance)}\n`;
        console.log(csvString);
      }

      await fsExtra.outputFile(csvOut, csvString);

      console.log(`Gathered info about post migration holders to ${csvOut}`);
    });