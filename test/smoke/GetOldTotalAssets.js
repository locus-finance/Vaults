const helpers = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");

describe("GetOldTotalAssets", () => {
  it('should get old total assets', async () => {
    const vault = "0x65b08FFA1C0E1679228936c0c85180871789E1d7";
    const vaultInstance = await ethers.getContractAt(
      "OnChainVault",
      vault
    );
    console.log(ethers.utils.formatUnits(await vaultInstance.totalAssets(), 6));
  });
});