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
  const xMantleVaultDepositaryAddress = "0xd26b740A6C69fcB314159C7f3D514776bEa52C12";
  const xMantleVaultTokenAddress = "0x46cBdEC2C229368091227c2073A64d5AC87CbEc5";
  
  const userAddress = "0x3C2792d5Ea8f9C03e8E73738E9Ed157aeB4FeCBe";
  
  const initStrategyAddress = "0xF74684Ec040edAE6De243B0DC748d19897E84e4C";
  const lendWmntStrategyAddress = "0x0018C5bcd6ac4DFBDD51C84A0af83575D45b3991";
  const moeWmntStrategyAddress = "0xC29aa574AaE5cD68209811e2Cd2aAA08E13bA638";
  const methWethStrategyAddress = "0x91E8535b64c74C5bDBf436308dF3789c7A3d1C4D";
  const wmntMethStrategyAddress = "0x0bE36BCF77f39360Ac47a697929C3ec907e5a99f";

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
    // const t = await hre.ethers.getContractAt("IERC20Metadata", "0xc37c7dEBa5E7F5dE572C914D5c159EA08DE1fefF");
    // console.log(await t.decimals());

    const time = 604800 + 3600;
    const slippage = 5000;
    await helpers.time.increase(time);
    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await usdcInstance.connect(userSigner).approve(xMantleInstance.address, usdcAmountToDeposit);
      await xMantleInstance.connect(userSigner)["deposit(uint256)"](usdcAmountToDeposit);
    });
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
    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await wmntMethStrategyInstance.connect(userSigner).setSlippage(slippage);
      await wmntMethStrategyInstance.connect(userSigner).updateOracle();
      await wmntMethStrategyInstance.connect(userSigner).harvest();
    });
    console.log('Post wmnt meth');
    console.log(hre.ethers.utils.formatUnits(await xMantleInstance.pricePerShare(), 6));
  });
});

