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
  const lendingPoolAddress = "0x00A55649E597d463fD212fBE48a3B40f0E227d06";
  const initStrategyAddress = "0xB134814B4E95DbD76fbc12E1976C8f54CD7b8020";
  const usdcUsdyStrategyAddress = "0xa28e09cC6fb46D49686DDe0aE48053600c94900f";
  const locusFeedAddress = "0x5662AaAc9fdc97910E648e54076Be71D60D4045f";
  
  const usdcWhale = "0x588846213A30fd36244e0ae0eBB2374516dA836C";

  const userUsdcAllowance = hre.ethers.BigNumber.from("5000000000");
  const strategist = "0x3C2792d5Ea8f9C03e8E73738E9Ed157aeB4FeCBe";
  const usdcAddress = "0x09Bc4E0D864854c6aFB6eB9A9cdF58aC190D0dF9";
  const usdcAmountToDeposit = hre.ethers.utils.parseUnits("4", 6);

  let xMantleInstance;
  let xMantleTokenInstance;
  let usdcInstance;
  let lendingPoolEip20Instance;
  let lendingPoolInstance;
  let initStrategyInstance;
  let usdcUsdyStrategyInstance;
  let locusFeedInstance;

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
    lendingPoolEip20Instance = await hre.ethers.getContractAt(
      "IERC20",
      lendingPoolAddress
    );
    lendingPoolInstance = await hre.ethers.getContractAt(
      "ILendingPool",
      lendingPoolAddress
    );
    initStrategyInstance = await hre.ethers.getContractAt(
      "InitStrategy",
      initStrategyAddress
    );
    usdcUsdyStrategyInstance = await hre.ethers.getContractAt(
      "UsdcUsdyStrategy",
      usdcUsdyStrategyAddress
    );
    locusFeedInstance = await hre.ethers.getContractAt(
      "LocusDataFeed",
      locusFeedAddress
    );
    await mintNativeTokens(userAddress, "0x10000000000000000000");
    await withImpersonatedSigner(usdcWhale, async (usdcWhaleSigner) => {
      await usdcInstance.connect(usdcWhaleSigner).transfer(userAddress, userUsdcAllowance);
    });
  });

  xit('should perform deposit', async () => {
    console.log(hre.ethers.utils.formatUnits(await usdcInstance.balanceOf(userAddress), 6));
    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await xMantleInstance.connect(userSigner)["deposit(uint256)"](usdcAmountToDeposit);
    });
  });

  it('should', async () => {
    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await xMantleInstance.connect(userSigner)["deposit(uint256)"](usdcAmountToDeposit);
    });
    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await initStrategyInstance.connect(userSigner).harvest();
    });
    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await locusFeedInstance.connect(userSigner).updateFeed(usdcUsdyStrategyAddress);
      await usdcUsdyStrategyInstance.connect(userSigner).harvest();
    });
  });

  xit('should EST', async () => {
    const cirVault = await hre.ethers.getContractAt("IERC20Metadata", "0xc425a0fc1e62beda428ff628597dc8ea1c13d0e4")
    console.log((await cirVault.decimals()).toString());
    const cirBalance = await cirVault.balanceOf(usdcUsdyStrategyInstance.address);
    console.log(cirBalance.toString());
    console.log((await usdcUsdyStrategyInstance.circuitSharesToWant(cirBalance)).toString());
    console.log(hre.ethers.utils.formatUnits(await xMantleInstance.pricePerShare()));
  });
});

