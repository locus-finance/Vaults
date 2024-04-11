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
  const xMantleVaultAddress = "0x4488B69067eaE5e201A7330C56198Aba5a595E3F";
  const userAddress = "0x3C2792d5Ea8f9C03e8E73738E9Ed157aeB4FeCBe";
  const lendingPoolAddress = "0x00A55649E597d463fD212fBE48a3B40f0E227d06";
  const initStrategyAddress = "0xc9C9cf5EAd9e299620dA6b668ae2A48E16883EF4";
  const usdcWhale = "0x588846213A30fd36244e0ae0eBB2374516dA836C";

  const userUsdcAllowance = hre.ethers.BigNumber.from("5000000000");
  const strategist = "0x3C2792d5Ea8f9C03e8E73738E9Ed157aeB4FeCBe";
  const usdcAddress = "0x09Bc4E0D864854c6aFB6eB9A9cdF58aC190D0dF9";
  const usdcAmountToDeposit = hre.ethers.utils.parseUnits("5", 6);

  let xMantleInstance;
  let usdcInstance;
  let lendingPoolEip20Instance;
  let lendingPoolInstance;
  let initStrategyInstance;

  beforeEach(async () => {
    xMantleInstance = await hre.ethers.getContractAt(
      "OnChainVault",
      xMantleVaultAddress
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
    await mintNativeTokens(userAddress, "0x10000000000000000000");
    await withImpersonatedSigner(usdcWhale, async (usdcWhaleSigner) => {
      await usdcInstance.connect(usdcWhaleSigner).transfer(userAddress, userUsdcAllowance);
    });
  });

  xit('should perform deposit', async () => {
    console.log(hre.ethers.utils.formatUnits(await usdcInstance.balanceOf(userAddress), 6));
    await withImpersonatedSigner(strategist, async (strategistSigner) => {
      await xMantleInstance.connect(strategistSigner).setDepositLimit(hre.ethers.constants.MaxUint256);
    });
    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await xMantleInstance.connect(userSigner)["deposit(uint256)"](usdcAmountToDeposit);
    });
  });

  it('should', async () => {
    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await xMantleInstance.connect(userSigner)["deposit(uint256)"](usdcAmountToDeposit);
    });
    console.log((await initStrategyInstance.estimatedTotalAssets()).toString());
    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await initStrategyInstance.connect(userSigner).harvest();
    });
    console.log((await initStrategyInstance.balanceOfShares()).toString());
    console.log((await initStrategyInstance.estimatedTotalAssets()).toString());
    console.log((await xMantleInstance.pricePerShare()).toString());
  });
});

