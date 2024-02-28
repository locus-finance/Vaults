const { expect } = require("chai");

const helpers = require("@nomicfoundation/hardhat-network-helpers");
const mintNativeTokens = async (signer, amountHex) => {
  await hre.network.provider.send("hardhat_setBalance", [
    signer.address || signer,
    amountHex
  ]);
}

const withImpersonatedSigner = async (signerAddress, action) => {
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [signerAddress],
  });

  const impersonatedSigner = await hre.ethers.getSigner(signerAddress);
  await action(impersonatedSigner);

  await hre.network.provider.request({
    method: "hardhat_stopImpersonatingAccount",
    params: [signerAddress],
  });
}

describe('TestSimpleMigration', () => {
    const userAddress = "0x263a8a1297582c307A008DE90372fbC98bEC1BA8";
    const userXDefiAllowance = hre.ethers.BigNumber.from("1888597014");
    const userXEthAllowance = hre.ethers.BigNumber.from("1349475625648352000");

    let simpleMigrationForXEthInstance;
    let simpleMigrationForXDefiInstance;
    let migrationsOwner;
    let xEthInstance;
    let xDefiInstance;

    beforeEach(async () => {
        simpleMigrationForXEthInstance = await hre.ethers.getContractAt(
            "SimpleMigration",
            "0x9C073294BaFcD23150bA3364DaBE37571b47Dabd"
        );
        simpleMigrationForXDefiInstance = await hre.ethers.getContractAt(
            "SimpleMigration",
            "0x381D91367317A9edb49C770ffaDe27FE91c977F5"
        );
        migrationsOwner = await simpleMigrationForXDefiInstance.owner();
        xEthInstance = await hre.ethers.getContractAt(
            "IERC20",
            await simpleMigrationForXEthInstance.vaultV2()
        );
        xDefiInstance = await hre.ethers.getContractAt(
            "IERC20",
            await simpleMigrationForXDefiInstance.vaultV2()
        );
        await mintNativeTokens(migrationsOwner, "0x10000000000000000000");
    });

    it('should migrate xEth for the user', async () => {
        await withImpersonatedSigner(migrationsOwner, async (owner) => {
            console.log(`xEth before: ${(await xEthInstance.balanceOf(userAddress)).toString()}`);
            const migrateUserTx = await simpleMigrationForXEthInstance.connect(owner).migrateUser(userAddress, userXEthAllowance);
            await migrateUserTx.wait();
            console.log(`xEth after: ${(await xEthInstance.balanceOf(userAddress)).toString()}`);
        });
    });

    it('should migrate xDefi for the user', async () => {
        await withImpersonatedSigner(migrationsOwner, async (owner) => {
            console.log(`xDefi before: ${(await xDefiInstance.balanceOf(userAddress)).toString()}`);
            const migrateUserTx = await simpleMigrationForXDefiInstance.connect(owner).migrateUser(userAddress, userXDefiAllowance);
            await migrateUserTx.wait();
            console.log(`xDefi after: ${(await xDefiInstance.balanceOf(userAddress)).toString()}`);
        });
    });
});

