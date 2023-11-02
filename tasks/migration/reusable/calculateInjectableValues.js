module.exports = (
  v1vault,
  blockNumber
) => async () => {
  console.log(`Using input params: v1vault=${v1vault}, blockNumber=${blockNumber}`);

  const oldVault = await hre.ethers.getContractAt(
    "OnChainVault",
    v1vault
  );

  const blockTimestamp = hre.ethers.BigNumber.from(
    (await hre.ethers.provider.getBlock(blockNumber)).timestamp
  );
  const lastReport = await oldVault.lastReport();
  const lockedProfitDegradation = await oldVault.lockedProfitDegradation();
  const lockedFundsRatio = blockTimestamp
    .sub(lastReport)
    .mul(lockedProfitDegradation);
  const DEGRADATION_COEFFICIENT = hre.ethers.utils.parseEther("10");

  let lockedProfit = await oldVault.lockedProfit();
  if (lockedFundsRatio.lt(DEGRADATION_COEFFICIENT)) {
    lockedProfit = lockedProfit.sub(
      lockedFundsRatio.mul(lockedProfit).div(DEGRADATION_COEFFICIENT)
    );
  } else {
    lockedProfit = hre.ethers.constants.Zero;
  }

  const totalAssets = await oldVault.totalAssets();
  const freeFundsToInject = totalAssets.sub(lockedProfit);
  const totalSupplyToInject = await oldVault.totalSupply();

  console.log(`Total Supply to inject: ${totalSupplyToInject.toString()}`);
  console.log(`Free Funds to inject: ${freeFundsToInject.toString()}`);

  return {
    freeFundsToInject,
    totalSupplyToInject
  }
}