const helpers = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");

describe("GetOldTotalAssets", () => {
  it('should get old total assets', async () => {
    const vault = "0x6c090e79A9399c0003A310E219b2D5ed4E6b0428";
    const vaultInstance = await ethers.getContractAt(
      "OnChainVault",
      vault
    );
    console.log(ethers.utils.formatUnits(await vaultInstance.totalAssets(), 6));
  });
});