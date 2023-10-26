const csvParser = require("csv-parser");
const fsExtra = require("fs-extra");

const parseHoldersAndBalances = (addressKey, balanceKey, file) => {
  let result = [];
  return new Promise((resolve, reject) => {
    fsExtra.createReadStream(file)
      .on("error", error => {
        reject(error);
      })
      .pipe(csvParser())
      .on("data", data => result.push({
        address: data[addressKey],
        balance: data[balanceKey].toString().includes(',') ? hre.ethers.utils.parseEther(data[balanceKey].replace(",", "")) : hre.ethers.BigNumber.from(data[balanceKey])
      }))
      .on("end", () => {
        resolve(result);
      });
  });
}

module.exports = (
  csvAddressKey,
  csvBalanceKey,
  csvFileRelativePath,
  vaultAddress,
  dropperAddress,
  customSigner
) => async () => {
  const holdersInfo = await parseHoldersAndBalances(csvAddressKey, csvBalanceKey, csvFileRelativePath);
  
  console.log(`Using data source: ${csvFileRelativePath}`);

  const dropper = await hre.ethers.getContractAt(
    "Dropper",
    dropperAddress
  );

  if (customSigner !== undefined) {
    await dropper.connect(customSigner).setVault(vaultAddress);
  } else {
    await dropper.setVault(vaultAddress);
  }

  const accounts = [];
  const balances = [];
  let totalBalances = hre.ethers.constants.Zero;
  for (const holderInfo of holdersInfo) {
    accounts.push(holderInfo.address);
    balances.push(holderInfo.balance);
    totalBalances = totalBalances.add(holderInfo.balance);
  }

  console.log(`Amount to be dropped: ${hre.ethers.utils.formatEther(totalBalances)}, for ${accounts.length} accounts.`);

  let dropTx;
  if (customSigner !== undefined) {
    dropTx = await dropper.connect(customSigner).drop(accounts, balances);
  } else {
    dropTx = await dropper.drop(accounts, balances);
  }
  const end = await dropTx.wait();

  console.log(`Cumulative gas used: ${end.cumulativeGasUsed}`);
  console.log(`Effective gas price: ${end.effectiveGasPrice}`);
  console.log('---');

  return {
    totalBalances,
    accounts,
    balances
  }
}