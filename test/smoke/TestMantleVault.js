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

describe('TestMantleVaultDeposit', () => {
  const xMantleVaultDepositaryAddress = "0x877559B8D37E5a05dB12F289214c51D05856fcA0";
  const xMantleVaultTokenAddress = "0xE6B9b205C290D077e56e4857beF082C2FFeF4C54";
  
  const userAddress = "0x3C2792d5Ea8f9C03e8E73738E9Ed157aeB4FeCBe";
  
  const initStrategyAddress = "0xB134814B4E95DbD76fbc12E1976C8f54CD7b8020";
  const usdcUsdyStrategyAddress = "0xB6582a1Ab673C514d0311332E39F7f305a78aC4a";
  const lendWmntStrategyAddress = "0x6667a54f0F3E9f6D97499b2404d6282b4a321f43";
  const moeWmntStrategyAddress = "0x0Fe16A7Bc673B92014D6f1e4D88355499D40671D";
  const methWethStrategyAddress = "0xFCE625E69Bd4952417Fe628bC63D9AA0e4012684";
  const wmntMethStrategyAddress = "0x977b3A2E8022dd9B8aF97C72B71409171B5394A8";

  const usdcWhale = "0x588846213A30fd36244e0ae0eBB2374516dA836C";
  const userUsdcAllowance = hre.ethers.utils.parseUnits("50000", 6);
  const usdcAddress = "0x09Bc4E0D864854c6aFB6eB9A9cdF58aC190D0dF9";
  const usdcAmountToDeposit = hre.ethers.utils.parseUnits("10000", 6);

  let xMantleInstance;
  let xMantleTokenInstance;
  
  let usdcInstance;
  
  let initStrategyInstance;
  let usdcUsdyStrategyInstance;
  let lendWmntStrategyInstance;
  let moeWmntStrategyInstance;
  let methWethStrategyInstance;
  let wmntMethStrategyInstance;
  
  beforeEach(async () => {
    xMantleInstance = await hre.ethers.getContractAt(
      "LocusVault",
      xMantleVaultDepositaryAddress
    );
    xMantleTokenInstance = await hre.ethers.getContractAt(
      "LocusVaultToken",
      xMantleVaultTokenAddress
    );
    usdcInstance = await hre.ethers.getContractAt(
      "IERC20",
      usdcAddress
    );
    initStrategyInstance = await hre.ethers.getContractAt(
      "InitStrategy",
      initStrategyAddress
    );
    usdcUsdyStrategyInstance = await hre.ethers.getContractAt(
      "UsdcUsdyStrategy",
      usdcUsdyStrategyAddress
    );
    lendWmntStrategyInstance = await hre.ethers.getContractAt(
      "LendWmntStrategy",
      lendWmntStrategyAddress
    );
    moeWmntStrategyInstance = await hre.ethers.getContractAt(
      "MoeWmntStrategy",
      moeWmntStrategyAddress
    );
    methWethStrategyInstance = await hre.ethers.getContractAt(
      "MethWethStrategy",
      methWethStrategyAddress
    );
    wmntMethStrategyInstance = await hre.ethers.getContractAt(
      "WmntMethStrategy",
      wmntMethStrategyAddress
    );

    await mintNativeTokens(userAddress, "0x10000000000000000000");
    await withImpersonatedSigner(usdcWhale, async (usdcWhaleSigner) => {
      await usdcInstance.connect(usdcWhaleSigner).transfer(userAddress, userUsdcAllowance);
    });
  });

  it('should deposit and harvest', async () => {
    const time = 604800 + 3600;
    const day = 86400;
    const agniTwapRangeSecs = 3600;//day * 7;
    console.log(hre.ethers.utils.formatUnits(await xMantleInstance.pricePerShare(), 6));
    await helpers.time.increase(time);
    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await usdcInstance.connect(userSigner).approve(xMantleInstance.address, usdcAmountToDeposit);
      await xMantleInstance.connect(userSigner)["deposit(uint256)"](usdcAmountToDeposit);
    });
    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await initStrategyInstance.connect(userSigner).harvest();
    });
    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await usdcUsdyStrategyInstance.connect(userSigner).updateOracle();
      await usdcUsdyStrategyInstance.connect(userSigner).harvest();
    });
    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await lendWmntStrategyInstance.connect(userSigner).setAgniTwapRangeSecs(agniTwapRangeSecs);
      await lendWmntStrategyInstance.connect(userSigner).updateOracle();
      await lendWmntStrategyInstance.connect(userSigner).harvest();
    });
    // await withImpersonatedSigner(userAddress, async (userSigner) => {
    //   await moeWmntStrategyInstance.connect(userSigner).updateOracle();
    //   await moeWmntStrategyInstance.connect(userSigner).harvest();
    // });
    // await withImpersonatedSigner(userAddress, async (userSigner) => {
    //   await methWethStrategyInstance.connect(userSigner).updateOracle();
    //   await methWethStrategyInstance.connect(userSigner).harvest();
    // });
    // await withImpersonatedSigner(userAddress, async (userSigner) => {
    //   await wmntMethStrategyInstance.connect(userSigner).updateOracle();
    //   await wmntMethStrategyInstance.connect(userSigner).harvest();
    // });
    console.log(hre.ethers.utils.formatUnits(await xMantleInstance.pricePerShare(), 6));
  });
});

