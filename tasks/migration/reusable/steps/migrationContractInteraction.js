const calculateInjectableValues = require('../calculateInjectableValues');

module.exports = (customSigner) =>
  async (taskParams, hre) => {
    const { v2vault, v1vault, migration } = taskParams;
    
    const v2vaultInstance = await hre.ethers.getContractAt(
      "OnChainVault",
      v2vault
    );
    const migrationInstance = await hre.ethers.getContractAt(
      "Migration",
      migration
    );

    let withdrawTx;
    if (customSigner !== undefined) {
      withdrawTx = await migrationInstance.connect(customSigner).withdraw();
    } else {
      withdrawTx = await migrationInstance.withdraw();
    }
    await withdrawTx.wait();

    if (!(await v2vaultInstance.isInjectedOnce())) {
      console.log(`A v2vault: ${v2vaultInstance.address} was not injected. Injecting...`);

      const { totalSupplyToInject, freeFundsToInject } = await calculateInjectableValues(v1vault, parseInt(process.env.ETH_FORK_BLOCK))();

      let injectTx;
      if (customSigner !== undefined) {
        injectTx = await v2vaultInstance.connect(customSigner).injectForMigration(totalSupplyToInject, freeFundsToInject);
      } else {
        injectTx = await v2vaultInstance.injectForMigration(totalSupplyToInject, freeFundsToInject);
      }
      await injectTx.wait();
    } else {
      console.log(`A v2vault ${v2vaultInstance.address} is already injected. Continue...`);
    }

    let setDepositLimitTx;
    let depositTx;
    if (customSigner !== undefined) {
      setDepositLimitTx = await v2vaultInstance.connect(customSigner).setDepositLimit(hre.ethers.constants.MaxUint256);
      await setDepositLimitTx.wait();

      depositTx = await migrationInstance.connect(customSigner).deposit();
      await depositTx.wait();
    } else {
      setDepositLimitTx = await v2vaultInstance.setDepositLimit(hre.ethers.constants.MaxUint256);
      await setDepositLimitTx.wait();

      depositTx = await migrationInstance.deposit();
      await depositTx.wait();
    }
  };