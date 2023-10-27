const calculateInjectableValues = require('./calculateInjectableValues');
const executeDrop = require('./executeDrop');

module.exports = (customSigner) =>
  async ({ v2vault, v1vault, dropper, migration, csv }, hre) => {
    const v2vaultInstance = await hre.ethers.getContractAt(
      "OnChainVault",
      v2vault
    );
    const migrationInstance = await hre.ethers.getContractAt(
      "Migration",
      migration
    );
    const treasury = await migrationInstance.treasury();

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
    }

    let setDepositLimitTx;
    let depositTx;
    let emergencyExitTx;
    let transferTx;
    if (customSigner !== undefined) {
      setDepositLimitTx = await v2vaultInstance.connect(customSigner).setDepositLimit(hre.ethers.constants.MaxUint256);
      await setDepositLimitTx.wait();

      depositTx = await migrationInstance.connect(customSigner).deposit();
      await depositTx.wait();

      emergencyExitTx = await migrationInstance.connect(customSigner).emergencyExit();
      await emergencyExitTx.wait();

      transferTx = await v2vaultInstance.connect(customSigner).transfer(
        dropper,
        await v2vaultInstance.balanceOf(treasury)
      );
      await transferTx.wait();
    } else {
      setDepositLimitTx = await v2vaultInstance.setDepositLimit(hre.ethers.constants.MaxUint256);
      await setDepositLimitTx.wait();

      depositTx = await migrationInstance.deposit();
      await depositTx.wait();

      emergencyExitTx = await migrationInstance.emergencyExit();
      await emergencyExitTx.wait();

      transferTx = await v2vaultInstance.transfer(
        dropper,
        await v2vaultInstance.balanceOf(treasury)
      );
      await transferTx.wait();
    }

    console.log(`Actual balance of the Dropper: ${hre.ethers.utils.formatUnits(await v2vaultInstance.balanceOf(dropper.address))}`);

    const csvFileName = `./tasks/migration/csv/${csv}`;

    const maxAmountOfUsers = await hre.run("countDropReceiversFromMigration", {
      migration
    });

    await hre.run('saveDropReceiversFromMigration', {
      migration,
      csv: csvFileName,
      count: maxAmountOfUsers
    });

    await executeDrop(
      'receiver',
      'balance',
      csvFileName,
      v2vault,
      dropper,
      customSigner
    )();
  };