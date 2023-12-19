const helpers = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");

const executeDropActionBuilder = require('../../tasks/migration/reusable/executeDrop');
const dropperContractInteractionActionBuilder = require('../../tasks/migration/reusable/steps/dropperContractInteraction');
const migrationContractInteractionActionBuilder = require('../../tasks/migration/reusable/steps/migrationContractInteraction');
const migrationContractPopulationActionBuilder = require('../../tasks/migration/reusable/migrationContractPopulation');
const additionalDropActionBuilder = require('../../tasks/migration/reusable/additionalDrop');

upgrades.silenceWarnings();

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

describe("DropTest", () => {
  it('should make drop', async () => {
    const owner = "0x27f52fd2E60B1153CBD00D465F97C05245D22B82";
    const person = "0x78173cAdc97432e09d6D00d7894b4074B83762C3";
    const amount = hre.ethers.BigNumber.from('49680859744544556');
    const dropper = await ethers.getContractAt(
      "Dropper",
      "0xEB20d24d42110B586B3bc433E331Fe7CC32D1471"
    );
    await withImpersonatedSigner(owner, async (ownerSigner) => {
      // await mintNativeTokens(owner, "0x100000000000000000");
      // await dropper.connect(ownerSigner).drop([person], [amount]);
      console.log((await dropper.connect(ownerSigner).estimateGas.emergencyExit()).toString());
    });
  });
});
