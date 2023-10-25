const {
    loadFixture,
  } = require("@nomicfoundation/hardhat-network-helpers");
  const { expect } = require("chai");
  const { utils } = require("ethers");
  const { ethers } = require("hardhat");
  
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
  

  describe("TotalAssetsTest", () => {
  
    it("should make it", async function () {
      const vault = await ethers.getContractAt(
        "OnChainVault",
        "0x0f094F6DEB056aF1fA1299168188fd8C78542A07"
      );
      console.log((await vault.totalAssets()).toString());
    });
  });
  