const csvParser = require("csv-parser");
const fsExtra = require("fs-extra");

module.exports = (addressKey, balanceKey, file, balanceFormatter=hre.ethers.BigNumber.from, addressFormatter=undefined) => {
  let result = [];
  return new Promise((resolve, reject) => {
    fsExtra.createReadStream(file)
      .on("error", error => {
        reject(error);
      })
      .pipe(csvParser())
      .on("data", data => result.push({
        address: addressFormatter !== undefined ? addressFormatter(data[addressKey]) : data[addressKey],
        balance: balanceFormatter(data[balanceKey])
      }))
      .on("end", () => {
        resolve(result);
      });
  });
}