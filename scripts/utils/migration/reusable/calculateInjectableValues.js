const { ethers } = require("hardhat");

module.exports = (
  oldVaultAddress,
  blockNumber
) => async () => {
  console.log(`Using input params: oldVaultAddress=${oldVaultAddress}, blockNumber=${blockNumber}`);

  const oldVault = await ethers.getContractAt(
    "OnChainVault",
    oldVaultAddress
  );

  const blockTimestamp = ethers.BigNumber.from(
    (await ethers.provider.getBlock(blockNumber)).timestamp
  );
  const lastReport = await oldVault.lastReport();
  const lockedProfitDegradation = await oldVault.lockedProfitDegradation();
  const lockedFundsRatio = blockTimestamp
    .sub(lastReport)
    .mul(lockedProfitDegradation);
  const DEGRADATION_COEFFICIENT = ethers.utils.parseEther("10");

  let lockedProfit = await oldVault.lockedProfit();
  if (lockedFundsRatio.lt(DEGRADATION_COEFFICIENT)) {
    lockedProfit = lockedProfit.sub(
      lockedFundsRatio.mul(lockedProfit).div(DEGRADATION_COEFFICIENT)
    );
  } else {
    lockedProfit = ethers.constants.Zero;
  }

  const totalAssets = await oldVault.totalAssets();
  const freeFundsToInject = totalAssets.sub(lockedProfit);
  const totalSupplyToInject = await oldVault.totalSupply();

  console.log(`Total Supply to inject: ${totalSupplyToInject.toString()}`);
  console.log(`Free Funds to inject: ${freeFundsToInject.toString()}`);
  console.log('---');
}