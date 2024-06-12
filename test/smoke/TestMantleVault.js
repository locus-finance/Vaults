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
  const lendWmntStrategyAddress = "0x71C98b0C970f612187cB0972Fb24C2830B07aF65";
  const moeWmntStrategyAddress = "0xC478d9361d8D98A4124878a813b3fde846Ba5A7F";
  const methWethStrategyAddress = "0xE1657ec6BdD12EcEcd840ff411E8D83f8BD84c03";
  const wmntMethStrategyAddress = "0x7C304B266245b29082F96D35298e7B8fc08cEcF9";

  const usdcWhale = "0x588846213A30fd36244e0ae0eBB2374516dA836C";
  const userUsdcAllowance = hre.ethers.utils.parseUnits("50000", 6);
  const usdcAddress = "0x09Bc4E0D864854c6aFB6eB9A9cdF58aC190D0dF9";
  const usdcAmountToDeposit = hre.ethers.utils.parseUnits("100", 6);

  let xMantleInstance;
  let xMantleTokenInstance;
  
  let usdcInstance;
  
  let initStrategyInstance;
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
    const slippage = 5000;
    await helpers.time.increase(time);
    
    const activeStrategies = [];
    const length = 49;
    for (let i = 0; i < length; i++) {
      const strategyAddr = await xMantleInstance.strategiesList(i);
      const strategyInfo = await xMantleInstance.getStrategyParams(strategyAddr);
      if (strategyInfo.debtRatio.gt(0)) {
        activeStrategies.push(strategyAddr);
      }
    }
    console.log(activeStrategies);

    // await withImpersonatedSigner(userAddress, async (userSigner) => {
    //   await usdcInstance.connect(userSigner).approve(xMantleInstance.address, usdcAmountToDeposit);
    //   await xMantleInstance.connect(userSigner)["deposit(uint256)"](usdcAmountToDeposit);
    // });
    // await withImpersonatedSigner(userAddress, async (userSigner) => {
    //   await initStrategyInstance.connect(userSigner).harvest();
    // });
    // console.log('Post init');
    // console.log(hre.ethers.utils.formatUnits(await xMantleInstance.pricePerShare(), 6));
    // await withImpersonatedSigner(userAddress, async (userSigner) => {
    //   await lendWmntStrategyInstance.connect(userSigner).setSlippage(slippage);
    //   await lendWmntStrategyInstance.connect(userSigner).updateOracle();
    //   await lendWmntStrategyInstance.connect(userSigner).harvest();
    // });
    // console.log('Post lend wmnt');
    // console.log(hre.ethers.utils.formatUnits(await xMantleInstance.pricePerShare(), 6));
    // await withImpersonatedSigner(userAddress, async (userSigner) => {
    //   await moeWmntStrategyInstance.connect(userSigner).setSlippage(slippage);
    //   await moeWmntStrategyInstance.connect(userSigner).updateOracle();
    //   await moeWmntStrategyInstance.connect(userSigner).harvest();
    // });
    // console.log('Post moe wmnt');
    // console.log(hre.ethers.utils.formatUnits(await xMantleInstance.pricePerShare(), 6));
    // await withImpersonatedSigner(userAddress, async (userSigner) => {
    //   await methWethStrategyInstance.connect(userSigner).setSlippage(slippage);
    //   await methWethStrategyInstance.connect(userSigner).updateOracle();
    //   await methWethStrategyInstance.connect(userSigner).harvest();
    // });
    // console.log('Post meth weth');
    // console.log(hre.ethers.utils.formatUnits(await xMantleInstance.pricePerShare(), 6));
    // await withImpersonatedSigner(userAddress, async (userSigner) => {
    //   await wmntMethStrategyInstance.connect(userSigner).setSlippage(slippage);
    //   await wmntMethStrategyInstance.connect(userSigner).updateOracle();
    //   await wmntMethStrategyInstance.connect(userSigner).harvest();
    // });
    // console.log('Post wmnt meth');
    // console.log(hre.ethers.utils.formatUnits(await xMantleInstance.pricePerShare(), 6));
  });
});

