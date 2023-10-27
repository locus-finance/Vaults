module.exports = (customSigner) =>
  async (taskParams, hre) => {
    const { v2vault, dropper, migration } = taskParams;
    const v2vaultInstance = await hre.ethers.getContractAt(
      "OnChainVault",
      v2vault
    );

    const migrationInstance = await hre.ethers.getContractAt(
      "Migration",
      migration
    );
    const treasury = await migrationInstance.treasury();

    let transferTx;
    if (customSigner !== undefined) {
      transferTx = await v2vaultInstance.connect(customSigner).transfer(
        dropper,
        await v2vaultInstance.balanceOf(treasury)
      );
      await transferTx.wait();
    } else {
      transferTx = await v2vaultInstance.transfer(
        dropper,
        await v2vaultInstance.balanceOf(treasury)
      );
      await transferTx.wait();
    }

    console.log(`Actual balance of the Dropper: ${hre.ethers.utils.formatUnits(await v2vaultInstance.balanceOf(dropper))}`);
  };