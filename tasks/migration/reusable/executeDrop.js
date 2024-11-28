const parseHoldersAndBalances = require("./parseHoldersAndBalances");

module.exports = (
  csvAddressKey,
  csvBalanceKey,
  csvFileRelativePath,
  vaultV2Address,
  dropperAddress,
  customSigner,
  popLast=false
) => async () => {
  const holdersInfo = await parseHoldersAndBalances(csvAddressKey, csvBalanceKey, csvFileRelativePath, hre.ethers.BigNumber.from);
  
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

  // true if funds are not enough to distribute
  if (popLast) {
    accounts.pop();
    balances.pop();
  }

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