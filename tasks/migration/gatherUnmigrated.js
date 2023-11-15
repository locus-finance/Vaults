const parseHoldersAndBalances = require('./reusable/parseHoldersAndBalances');
const fsExtra = require('fs-extra');

module.exports = (task) =>
  task(
    "gatherUnmigrated",
    "Saves into CSV file addresses and approves of unmigrated fellows.",
  )
    .addOptionalParam('v1vault', "Define from where the migration should occur.", '0x3edbE670D03C4A71367dedA78E73EA4f8d68F2E4', types.string)
    .addOptionalParam('migration', "Define from where the task should gather the drop receivers.", '0xd25d0de43579223429c28f2d64183a47a79078C7', types.string)
    .addOptionalParam('csvIn', "Define a relative path for CSV file of holders.", './tasks/migration/csv/postMigration/secondWave/lvEthV1HoldersPostMigration.csv', types.string)
    .addOptionalParam('csvOut', "Define a relative path for CSV file output information: holder - migration status.", './tasks/migration/csv/postMigration/secondWave/nonMigrated/lvEthV1HoldersNonMigrated.csv', types.string)
    .setAction(async ({ migration, v1vault, csvOut, csvIn }, hre) => {
      const migrationInstance = await hre.ethers.getContractAt(
        "Migration",
        migration
      );
      const v1vaultInstance = await hre.ethers.getContractAt(
        "OnChainVault",
        v1vault
      );

      let csvString = "\"receiver\",\"v1Balance\",\"allowanceToMigration\",\"includedInMigration\",\"registeredBalanceInMigration\"\n";

      await fsExtra.ensureFile(csvOut);

      const maxAmountOfUsers = await hre.run("countDropReceiversFromMigration", {
        migration
      });

      const isAddressIncludedInMigration = async (address) => {
        for (let i = 0; i < maxAmountOfUsers; i++) {
          const userAddress = await migrationInstance.users(i);
          if (address === userAddress) {
            return {
              included: true,
              registeredBalance: (await migrationInstance.userToBalance(userAddress)).toString()
            };
          }
        }
        return {
          included: false,
          registeredBalance: hre.ethers.constants.Zero
        };
      }

      const decimals = await v1vaultInstance.decimals();

      const parsedHolders = await parseHoldersAndBalances(
        "HolderAddress", 
        "Balance", 
        csvIn,
        (rawBalance) => rawBalance.includes(",")
          ? hre.ethers.utils.parseUnits(rawBalance.replace(",", ""), decimals)
          : hre.ethers.utils.parseUnits(rawBalance, decimals)
      );
      
      
      let allowancesSum = hre.ethers.constants.Zero;
      const pricePerShare = await v1vaultInstance.pricePerShare();

      for (const parsedHolder of parsedHolders) {
        console.log(`Processing:\n${JSON.stringify(parsedHolder)}`);
        const allowance = await v1vaultInstance.allowance(parsedHolder.address, migrationInstance.address);
        
        const isAddressIncludedInfo = await isAddressIncludedInMigration(parsedHolder.address);     
        csvString += `${parsedHolder.address},${parsedHolder.balance},${allowance.toString()},${isAddressIncludedInfo.included},${isAddressIncludedInfo.registeredBalance}\n`;
        console.log(csvString);
        allowancesSum = allowancesSum.add(allowance);
      }

      await fsExtra.outputFile(csvOut, csvString);

      console.log(`PPS: ${pricePerShare.toString()}`);
      console.log(`Allowances Sum: ${allowancesSum.toString()}`);
      console.log(`Gathered info about post migration holders to ${csvOut}`);
    });