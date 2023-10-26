const csvParser = require("csv-parser");
const fsExtra = require("fs-extra")

const parseHoldersAndBalances = file => {
  let result = [];
  return new Promise((resolve, reject) => {
    fsExtra.createReadStream(file)
      .on("error", error => {
        reject(error);
      })
      .pipe(csvParser())
      .on("data", data => result.push({
        address: data['HolderAddress'],
        balance: hre.ethers.utils.parseEther(data['Balance'].replace(",", ""))
      }))
      .on("end", () => {
        resolve(result);
      });
  });
}

module.exports = (
  csvFileRelativePath,
  vaultAddress,
  customSigner
) => async () => {
  const [deployer] = await hre.ethers.getSigners();
  const holdersInfo = await parseHoldersAndBalances(csvFileRelativePath);

  console.log(`Signer: ${deployer.address}`);
  console.log(`Using data source: ${csvFileRelativePath}`);

  const dropper = await hre.ethers.getContractAt(
    "Dropper",
    "0xEB20d24d42110B586B3bc433E331Fe7CC32D1471"
  );

  if (customSigner !== undefined) {
    await dropper.connect(customSigner).setVault(vaultAddress);
  } else {
    await dropper.setVault(vaultAddress);
  }

  const accounts = [];
  const balances = [];

  for (const holderInfo of holdersInfo) {
    accounts.push(holderInfo.address);
    balances.push(holderInfo.balance);
  }

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
}