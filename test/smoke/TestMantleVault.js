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
  const usdcUsdyStrategyAddress = "0x85342801C489F7807b2a11856E67Bbc38Fa7279e";
  const lendWmntStrategyAddress = "0x5B7F289994962B59043C57d719220f08127e8A8e";
  const moeWmntStrategyAddress = "0xADbDecc99FA05FD6DD7e882a48274E0A85Af0656";
  const methWethStrategyAddress = "0x4759217BbCBAAB2c605647B611D15dEC42133275";
  const wmntMethStrategyAddress = "0x06219C06A874172577c772f222FD9BFA43553Ba8";

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
    const time = 604800;
    // console.log(hre.ethers.utils.formatUnits(await xMantleInstance.pricePerShare(), 6));
    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await usdcInstance.connect(userSigner).approve(xMantleInstance.address, usdcAmountToDeposit);
      await xMantleInstance.connect(userSigner)["deposit(uint256)"](usdcAmountToDeposit);
    });
    // await withImpersonatedSigner(userAddress, async (userSigner) => {
    //   await initStrategyInstance.connect(userSigner).harvest();
    // });
    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await usdcUsdyStrategyInstance.connect(userSigner).updateOracle();
      console.log(await usdcUsdyStrategyInstance.connect(userSigner).checkFirstObservationInWindow("0xc1f43E45F86E7bfb92C3c309b0eF366F9Ba33Bfa"));
      await helpers.time.increase(time);
      await usdcUsdyStrategyInstance.connect(userSigner).updateOracle();
      console.log(await usdcUsdyStrategyInstance.connect(userSigner).checkFirstObservationInWindow("0xc1f43E45F86E7bfb92C3c309b0eF366F9Ba33Bfa"));
      
      // console.log((await usdcUsdyStrategyInstance.connect(userSigner).windowSize()).toString());
      // console.log((await usdcUsdyStrategyInstance.connect(userSigner).periodSize()).toString());
      // await usdcUsdyStrategyInstance.connect(userSigner).harvest();
    });
    // await withImpersonatedSigner(userAddress, async (userSigner) => {
    //   await usdcUsdyStrategyInstance.connect(userSigner).updateOracle();
    //   await helpers.time.increase(time);
    //   await usdcUsdyStrategyInstance.connect(userSigner).updateOracle();
    //   await lendWmntStrategyInstance.connect(userSigner).harvest();
    // });
    // await withImpersonatedSigner(userAddress, async (userSigner) => {
    //   await usdcUsdyStrategyInstance.connect(userSigner).updateOracle();
    //   await helpers.time.increase(time);
    //   await usdcUsdyStrategyInstance.connect(userSigner).updateOracle();
    //   await moeWmntStrategyInstance.connect(userSigner).harvest();
    // });
    // await withImpersonatedSigner(userAddress, async (userSigner) => {
    //   await usdcUsdyStrategyInstance.connect(userSigner).updateOracle();
    //   await helpers.time.increase(time);
    //   await usdcUsdyStrategyInstance.connect(userSigner).updateOracle();
    //   await methWethStrategyInstance.connect(userSigner).harvest();
    // });
    // await withImpersonatedSigner(userAddress, async (userSigner) => {
    //   await usdcUsdyStrategyInstance.connect(userSigner).updateOracle();
    //   await helpers.time.increase(time);
    //   await usdcUsdyStrategyInstance.connect(userSigner).updateOracle();
    //   await wmntMethStrategyInstance.connect(userSigner).harvest();
    // });
    // console.log(hre.ethers.utils.formatUnits(await xMantleInstance.pricePerShare(), 6));
  });
});

