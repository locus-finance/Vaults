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
        balance: hre.ethers.BigNumber.from(data[balanceKey])
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
  vaultV2Address,
  dropperAddress,
  customSigner
) => async () => {
  const holdersInfo = await parseHoldersAndBalances(csvAddressKey, csvBalanceKey, csvFileRelativePath);
  
  console.log(`Using data source: ${csvFileRelativePath}`);

  const dropper = await hre.ethers.getContractAt(
    "Dropper",
    dropperAddress
  );

  let setVaultTx;
  if (customSigner !== undefined) {
    setVaultTx = await dropper.connect(customSigner).setVault(vaultV2Address);
  } else {
    setVaultTx = await dropper.setVault(vaultV2Address);
  }
  await setVaultTx.wait();

  const accounts = [];
  const balances = [];
  let totalBalances = hre.ethers.constants.Zero;
  for (const holderInfo of holdersInfo) {
    if (holderInfo.balance.eq(hre.ethers.constants.Zero)) continue;
    accounts.push(holderInfo.address);
    balances.push(holderInfo.balance);
    totalBalances = totalBalances.add(holderInfo.balance);
  }

  accounts.pop();
  balances.pop();

  console.log(`Amount to be dropped: ${totalBalances.toString()} wei, for ${accounts.length} accounts.`);

  let dropTx;
  if (customSigner !== undefined) {
    dropTx = await dropper.connect(customSigner).drop(accounts, balances);
  } else {
    dropTx = await dropper.drop(accounts, balances);
  }
  const end = await dropTx.wait();

  console.log(`Cumulative gas used: ${end.cumulativeGasUsed}`);
  console.log(`Effective gas price: ${end.effectiveGasPrice}`);

  return {
    totalBalances,
    accounts,
    balances
  }
}