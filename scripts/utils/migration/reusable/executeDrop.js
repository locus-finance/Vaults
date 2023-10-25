const csvParser = require("csv-parser");
const { ethers } = require("hardhat");
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
        balance: ethers.utils.parseEther(data['Balance'].replace(",", ""))
      }))
      .on("end", () => {
        resolve(result);
      });
  });
}

module.exports = (
  csvFileRelativePath
) => async () => {
  const [deployer] = await ethers.getSigners();
  const holdersInfo = await parseHoldersAndBalances(csvFileRelativePath);
  console.log(holdersInfo);
}