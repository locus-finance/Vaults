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
  const xMantleVaultDepositaryAddress = "0x59EC16C1a3dCe0c9C2b07BB267005d3055a88e8d";
  const xMantleVaultTokenAddress = "0x24fE74805F46D9628c4F151684406eFC455D3BFE";

  const userAddress = "0x3C2792d5Ea8f9C03e8E73738E9Ed157aeB4FeCBe";

  const initStrategyAddress = "0x556475c398CcD0D7f067e580FB4F9A071c779210";
  const lendWmntStrategyAddress = "0x61D75dF86dC435A5C412d236f3D80C31A34f344D";
  const moeWmntStrategyAddress = "0x5944eeF6A82D484D0D4f59e49D6328C6BaE0bcfB";
  const methWethStrategyAddress = "0x35a34693a4Ef216b2C118e57f1418c5F934eB735";
  const wmntMethStrategyAddress = "0x873c65beb72F28232f4b81fdE8d04707894D47B1";

  const usdcWhale = "0x588846213A30fd36244e0ae0eBB2374516dA836C";
  const userUsdcAllowance = hre.ethers.utils.parseUnits("8665616.355424", 6);
  const usdcAddress = "0x09Bc4E0D864854c6aFB6eB9A9cdF58aC190D0dF9";

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

  xit('should not influence Circuit Vault PPS', async () => {
    console.log('Starting to gather all the dependencies and links onchain...');
    const deadline = (await hre.ethers.provider.getBlock()).timestamp + 100000;
    const moeRouterAddress = "0xeaEE7EE68874218c3558b40063c42B82D3E7232a";
    const moeRouterInstance = await hre.ethers.getContractAt("IMoeRouter", moeRouterAddress);

    const circuitVaultsAddresses = [
      "0x6CeaC8F90B7cAA311E025480503Bb0020B66f22A", // LEND WMNT
      "0x16FA0C5f3eA649259C02c075dbA1C31fc66ea4E0", // METH WETH
      "0xa3647389cf2bF9279ab239d3710bB8a2eFE0BC8B", // MOE WMNT
      "0xc37c7dEBa5E7F5dE572C914D5c159EA08DE1fefF" // WMNT METH
    ];

    const circuitVaultsInstances = [];
    const circuitVaultsWantTokensInstances = [];
    const circuitVaultsWantTokensUnderlyingsInstances = [];
    for (let i = 0; i < circuitVaultsAddresses.length; i++) {
      const vaultInstance = await hre.ethers.getContractAt("ICircuitVault", circuitVaultsAddresses[i]);
      circuitVaultsInstances.push(vaultInstance);

      const pairAddress = await vaultInstance.want();
      const moePairInstance = await hre.ethers.getContractAt("IMoePair", pairAddress);
      circuitVaultsWantTokensInstances.push(moePairInstance);
      
      const token0Instance = await hre.ethers.getContractAt(
        "IERC20Metadata",
        await moePairInstance.token0()
      );
      const token1Instance = await hre.ethers.getContractAt(
        "IERC20Metadata",
        await moePairInstance.token1()
      );

      circuitVaultsWantTokensUnderlyingsInstances.push([
        token0Instance,
        token1Instance,
      ]);
  
      const maxAllowance = hre.ethers.constants.MaxUint256;

      await withImpersonatedSigner(userAddress, async (userSigner) => {
        (await moePairInstance.connect(userSigner).approve(vaultInstance.address, maxAllowance)).wait();
        (await token0Instance.connect(userSigner).approve(moeRouterAddress, maxAllowance)).wait();
        (await token1Instance.connect(userSigner).approve(moeRouterAddress, maxAllowance)).wait();
        (await token0Instance.connect(userSigner).approve(moePairInstance.address, maxAllowance)).wait();
        (await token1Instance.connect(userSigner).approve(moePairInstance.address, maxAllowance)).wait();
      });
    }

    const lendWhale = "0xF6489621A9F5dA93B72a139ab75AeBf8fC70A1B0";
    const methWhale = "0x5071c003bB45e49110a905c1915EbdD2383A89dF";
    const wethWhale = "0x588846213A30fd36244e0ae0eBB2374516dA836C";
    const wmntWhale = "0x62351b47e060c61868Ab7E05920Cb42bD9A5f2B2";
    const moeWhale = "0x685489467Ff83E8fF3d1f63f86bE9b1425a0787d";

    const lendAddress = "0x25356aeca4210eF7553140edb9b8026089E49396";
    const methAddress = "0xcDA86A272531e8640cD7F1a92c01839911B90bb0";
    const wethAddress = "0xdEAddEaDdeadDEadDEADDEAddEADDEAddead1111";
    const wmntAddress = "0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8";
    const moeAddress = "0x4515A45337F461A11Ff0FE8aBF3c606AE5dC00c9";

    const tokensToWhales = {};
    tokensToWhales[lendAddress] = lendWhale;
    tokensToWhales[methAddress] = methWhale;
    tokensToWhales[wethAddress] = wethWhale;
    tokensToWhales[wmntAddress] = wmntWhale;
    tokensToWhales[moeAddress] = moeWhale;
    
    const maxBps = 10000;
    const partsOfWhalesBalances = [
      100,
      200,
      4000,
      5000
    ]

    const getFundsFromWhales = async (whalesBalancesPartToDeposit, token0, token1, wantInstance) => {
      const whaleToken0Address = tokensToWhales[token0.address];
      await mintNativeTokens(whaleToken0Address, "0x10000000000000000000");
      const whaleToken1Address = tokensToWhales[token1.address];
      await mintNativeTokens(whaleToken1Address, "0x10000000000000000000");
      
      const token0ToAddToLiquidity = (await token0.balanceOf(whaleToken0Address)).mul(whalesBalancesPartToDeposit).div(maxBps);
      const token1ToAddToLiquidity = (await token1.balanceOf(whaleToken1Address)).mul(whalesBalancesPartToDeposit).div(maxBps);

      const token0ToAddToLiquidityFormatted = hre.ethers.utils.formatUnits(
        token0ToAddToLiquidity,
        await token0.decimals()
      );
      const token1ToAddToLiquidityFormatted = hre.ethers.utils.formatUnits(
        token1ToAddToLiquidity,
        await token1.decimals()
      );
      console.log(`Using whales\' balances part of ${whalesBalancesPartToDeposit} BPS from whole: ${token0ToAddToLiquidityFormatted} ${await token0.symbol()} and ${token1ToAddToLiquidityFormatted} ${await token1.symbol()}`);

      await withImpersonatedSigner(whaleToken0Address, async (whale0Signer) => {
        (await token0.connect(whale0Signer).transfer(userAddress, token0ToAddToLiquidity)).wait();
      });
      await withImpersonatedSigner(whaleToken1Address, async (whale1Signer) => {
        (await token1.connect(whale1Signer).transfer(userAddress, token1ToAddToLiquidity)).wait();
      });

      console.log(`Whales\' funds acquired. Trying to add to Merchant Moe liquidity...`);

      await withImpersonatedSigner(userAddress, async (userSigner) => {
        const addLiquidityTx = await moeRouterInstance.connect(userSigner).addLiquidity(
          token0.address,
          token1.address,
          token0ToAddToLiquidity,
          token1ToAddToLiquidity,
          0,
          0,
          userAddress,
          deadline
        );
        await addLiquidityTx.wait();
      });
      const wantBalance = await wantInstance.balanceOf(userAddress);
      console.log(`LP tokens from whales support gathered: ${hre.ethers.utils.formatEther(wantBalance)} ${await wantInstance.symbol()}`);
      return wantBalance;
    }

    const depositIntoVault = async (vaultInstance, wantInstance, token0Instance, token1Instance, whalesBalancesPartToDeposit) => {
      const wantBalance = await getFundsFromWhales(whalesBalancesPartToDeposit, token0Instance, token1Instance, wantInstance);
      await withImpersonatedSigner(userAddress, async (userSigner) => {
        (await vaultInstance.connect(userSigner).deposit(wantBalance)).wait();
      });
      const vaultBalanceFormatted = hre.ethers.utils.formatEther(await vaultInstance.balanceOf(userAddress));
      console.log(`LP tokens deposited into vault ${await vaultInstance.name()}: ${hre.ethers.utils.formatEther(wantBalance)} minted ${vaultBalanceFormatted} ${await vaultInstance.symbol()}`);
    }
    const withdrawFromVault = async (vaultInstance, wantInstance) => {
      const vaultBalance = await vaultInstance.balanceOf(userAddress);
      await withImpersonatedSigner(userAddress, async (userSigner) => {
        (await vaultInstance.connect(userSigner).withdraw(vaultBalance)).wait();
      });
      const wantBalance = await wantInstance.balanceOf(userAddress);
      console.log(`LP tokens withdrawn from vault ${await vaultInstance.name()}: ${hre.ethers.utils.formatEther(wantBalance)}`);
    }

    const depositCalculatePpsAndWithdraw = async (vaultInstance, wantInstance, token0Instance, token1Instance, whalesBalancesPartToDeposit) => {
      const pricesPerFullShares = [];
      
      pricesPerFullShares.push((await vaultInstance.getPricePerFullShare()).toString());
      await depositIntoVault(vaultInstance, wantInstance, token0Instance, token1Instance, whalesBalancesPartToDeposit);
      pricesPerFullShares.push((await vaultInstance.getPricePerFullShare()).toString());
      await withdrawFromVault(vaultInstance, wantInstance);
      pricesPerFullShares.push((await vaultInstance.getPricePerFullShare()).toString());

      console.log(`PPS\' for vault ${await vaultInstance.name()} are gathered:`);
      console.log(pricesPerFullShares);
      return pricesPerFullShares;
    }

    console.log('All onchain links and dependencies are gathered. Starting to scan for PPS\' values...');
    const ppsLists = {};
    for (let i = 0; i < circuitVaultsInstances.length; i++) {
      const vault = circuitVaultsInstances[i];
      const moeLp = circuitVaultsWantTokensInstances[i];
      const token0 = circuitVaultsWantTokensUnderlyingsInstances[i][0];
      const token1 = circuitVaultsWantTokensUnderlyingsInstances[i][1];
      const vaultSymbol = await vault.symbol();
      const vaultName = await vault.name();
      console.log(`*** Gathering info for ${vaultName} (${vaultSymbol}) ***`);
      ppsLists[vaultSymbol] = {};
      for (let j = 0; j < partsOfWhalesBalances.length; j++) {
        ppsLists[vaultSymbol][`${partsOfWhalesBalances[j]}`] = await depositCalculatePpsAndWithdraw(
          vault, moeLp, token0, token1, partsOfWhalesBalances[j]
        );
      }
      console.log(`*** Info gathered for ${vaultName} (${vaultSymbol}) ***`);
    }
    console.log('------------------------------');
    console.log(ppsLists);
  });

  xit('should show something', async () => {
    const precision = hre.ethers.utils.parseEther("1");
    const circuitVaultAddr = "0x6CeaC8F90B7cAA311E025480503Bb0020B66f22A";
    const circuitVault = await hre.ethers.getContractAt("ICircuitVault", circuitVaultAddr);
    const pps = await circuitVault.getPricePerFullShare();
    const ts = await circuitVault.totalSupply();
    const balance = await circuitVault.balance();
    const expectedBalance = pps.mul(ts).div(precision);
    console.log(balance.toString());
    console.log(expectedBalance.toString());
    console.log("---");
    const expectedTotalSupply = balance.mul(precision).div(pps);
    console.log(expectedTotalSupply.toString());
    console.log(ts.toString());

    // console.log(await p.token0());
    // console.log(await p.token1());
    // const t = await hre.ethers.getContractAt("ICircuitVault", "0xc37c7dEBa5E7F5dE572C914D5c159EA08DE1fefF");
    // const t1 = await hre.ethers.getContractAt("IERC20", "0xa375ea3e1f92d62e3A71B668bAb09f7155267fa3")
    // console.log((await t.getPricePerFullShare()).toString());
    // console.log(hre.ethers.utils.formatEther(await t1.balanceOf(t.address)));
    // console.log(hre.ethers.utils.formatEther(await t1.balanceOf("0x95d270e8ea896a6e14d5b49cd06053f97ee579ef")));
  });

  const depositHarvestAndWithdraw = async (usdcAmountToDeposit) => {
    let ppsList = [];
    const week = 604800;
    const hour = 3600;
    const time = week + hour;
    const slippage = 1000;
    await helpers.time.increase(time);
    let oldBalanceUsdc;
    console.log('start pps');
    const startPps = hre.ethers.utils.formatUnits(await xMantleInstance.pricePerShare(), 6);
    ppsList.push(startPps);
    console.log(startPps);
    // console.log(`totalAssets() = ${hre.ethers.utils.formatUnits(await xMantleInstance.totalAssets(), 6)}`);
    // console.log(`totalIdle() = ${hre.ethers.utils.formatUnits(await xMantleInstance.totalIdle(), 6)}`);

    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await usdcInstance.connect(userSigner).approve(xMantleInstance.address, usdcAmountToDeposit);
      await xMantleInstance.connect(userSigner)["deposit(uint256)"](usdcAmountToDeposit);
      oldBalanceUsdc = await usdcInstance.balanceOf(userAddress);
      // console.log(`Start usdc balance after deposit: ${hre.ethers.utils.formatUnits(oldBalanceUsdc, 6)}`);
      // console.log(`Deposit usdc amount: ${hre.ethers.utils.formatUnits(usdcAmountToDeposit, 6)}`);
    });

    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await initStrategyInstance.connect(userSigner).harvest();
    });
    console.log('Post init');
    const postInitPps = hre.ethers.utils.formatUnits(await xMantleInstance.pricePerShare(), 6);
    ppsList.push(postInitPps);
    console.log(postInitPps);
    // console.log(`INIT total assets: ${hre.ethers.utils.formatUnits(await initStrategyInstance.estimatedTotalAssets(), 6)}`);
    // console.log(`totalAssets() = ${hre.ethers.utils.formatUnits(await xMantleInstance.totalAssets(), 6)}`);
    // console.log(`totalIdle() = ${hre.ethers.utils.formatUnits(await xMantleInstance.totalIdle(), 6)}`);

    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await lendWmntStrategyInstance.connect(userSigner).resetAllowances();
      await lendWmntStrategyInstance.connect(userSigner).setSlippage(slippage);
      await lendWmntStrategyInstance.connect(userSigner).updateOracle();
      await lendWmntStrategyInstance.connect(userSigner).harvest();
    });
    console.log('Post lend wmnt');
    const postLendWmntPps = hre.ethers.utils.formatUnits(await xMantleInstance.pricePerShare(), 6);
    ppsList.push(postLendWmntPps);
    console.log(postLendWmntPps);
    // console.log(`LEND WMNT total assets: ${hre.ethers.utils.formatUnits(await lendWmntStrategyInstance.estimatedTotalAssets(), 6)}`);
    // console.log(`totalAssets() = ${hre.ethers.utils.formatUnits(await xMantleInstance.totalAssets(), 6)}`);
    // console.log(`totalIdle() = ${hre.ethers.utils.formatUnits(await xMantleInstance.totalIdle(), 6)}`);

    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await moeWmntStrategyInstance.connect(userSigner).resetAllowances();
      await moeWmntStrategyInstance.connect(userSigner).setSlippage(slippage);
      await moeWmntStrategyInstance.connect(userSigner).updateOracle();
      await moeWmntStrategyInstance.connect(userSigner).harvest();
    });
    console.log('Post moe wmnt');
    const postMoeWmntPps = hre.ethers.utils.formatUnits(await xMantleInstance.pricePerShare(), 6);
    ppsList.push(postMoeWmntPps);
    console.log(postMoeWmntPps);
    // console.log(`MOE WMNT total assets: ${hre.ethers.utils.formatUnits(await moeWmntStrategyInstance.estimatedTotalAssets(), 6)}`);
    // console.log(`totalAssets() = ${hre.ethers.utils.formatUnits(await xMantleInstance.totalAssets(), 6)}`);
    // console.log(`totalIdle() = ${hre.ethers.utils.formatUnits(await xMantleInstance.totalIdle(), 6)}`);

    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await methWethStrategyInstance.connect(userSigner).resetAllowances();
      await methWethStrategyInstance.connect(userSigner).setSlippage(slippage);
      await methWethStrategyInstance.connect(userSigner).updateOracle();
      await methWethStrategyInstance.connect(userSigner).harvest();
    });
    console.log('Post meth weth');
    const postMethWethPps = hre.ethers.utils.formatUnits(await xMantleInstance.pricePerShare(), 6);
    ppsList.push(postMethWethPps);
    console.log(postMethWethPps);
    // console.log(`MOE WMNT total assets: ${hre.ethers.utils.formatUnits(await methWethStrategyInstance.estimatedTotalAssets(), 6)}`);
    // console.log(`totalAssets() = ${hre.ethers.utils.formatUnits(await xMantleInstance.totalAssets(), 6)}`);
    // console.log(`totalIdle() = ${hre.ethers.utils.formatUnits(await xMantleInstance.totalIdle(), 6)}`);

    await withImpersonatedSigner(userAddress, async (userSigner) => {
      await wmntMethStrategyInstance.connect(userSigner).resetAllowances();
      await wmntMethStrategyInstance.connect(userSigner).setSlippage(slippage);
      await wmntMethStrategyInstance.connect(userSigner).updateOracle();
      await wmntMethStrategyInstance.connect(userSigner).harvest();
    });
    console.log('Post wmnt meth');
    const postWmntMethPps = hre.ethers.utils.formatUnits(await xMantleInstance.pricePerShare(), 6);
    ppsList.push(postWmntMethPps);
    console.log(postWmntMethPps);
    // console.log(`MOE WMNT total assets: ${hre.ethers.utils.formatUnits(await wmntMethStrategyInstance.estimatedTotalAssets(), 6)}`);
    // console.log(`totalAssets() = ${hre.ethers.utils.formatUnits(await xMantleInstance.totalAssets(), 6)}`);
    // console.log(`totalIdle() = ${hre.ethers.utils.formatUnits(await xMantleInstance.totalIdle(), 6)}`);

    await helpers.time.increase(time * 100);
    console.log('Post time increase pps');
    console.log(hre.ethers.utils.formatUnits(await xMantleInstance.pricePerShare(), 6));
    
    await withImpersonatedSigner(userAddress, async (userSigner) => {
      const vaultBalance = await xMantleTokenInstance.balanceOf(userAddress);
      // console.log(`Vault balance to withdraw: ${hre.ethers.utils.formatUnits(vaultBalance, 18)}`);
      await xMantleInstance.connect(userSigner).withdraw(vaultBalance, userAddress, 5000);
      const newBalanceUsdc = await usdcInstance.balanceOf(userAddress);
      // console.log(`End usdc balance: ${hre.ethers.utils.formatUnits(newBalanceUsdc, 6)}`);
      console.log(`Usdc withdrawn: ${hre.ethers.utils.formatUnits(newBalanceUsdc.sub(oldBalanceUsdc), 6)}`);
      // console.log(`Deposited - withdrawn = ${hre.ethers.utils.formatUnits(usdcAmountToDeposit.sub(newBalanceUsdc.sub(oldBalanceUsdc)), 6)}`);
    });

    return ppsList;
  }

  xit('should deposit and harvest and withdraw - deposit amount grows', async () => {
    const ppsLists = [];
    for (let i = 1000; i <= 1000; i += 1000) {
      console.log(`Deposit amount: ${i}`);
      const usdcToDeposit = hre.ethers.utils.parseUnits(i.toString(), 6);
      try {
        const ppsList = await depositHarvestAndWithdraw(usdcToDeposit);
        ppsLists.push({
          deposit: i,
          ppsList
        });
      } catch {
        continue;
      }
    }
    let csv = "";
    for (const entry of ppsLists) {
      csv = `${csv}${entry.deposit}`;
      for (const pps of entry.ppsList) {
        csv = `${csv},${pps}`
      }
      csv += '\n';
    }
    console.log(csv);
  });

  xit('should deposit and harvest and withdraw - deposit amount constant', async () => {
    const ppsLists = [];
    const depositAmount = 1000;
    for (let i = 0; i <= 1; i += 1) {
      console.log(`Deposit amount: ${depositAmount}`);
      const usdcToDeposit = hre.ethers.utils.parseUnits(depositAmount.toString(), 6);
      try {
        const ppsList = await depositHarvestAndWithdraw(usdcToDeposit);
        ppsLists.push({
          deposit: depositAmount,
          ppsList
        });
      } catch {
        continue;
      }
    }
    console.log('CSV STARTS:');
    let csv = "";
    for (const entry of ppsLists) {
      csv = `${csv}${entry.deposit}`;
      for (const pps of entry.ppsList) {
        csv = `${csv},${pps}`
      }
      csv += '\n';
    }
    console.log(csv);
  });

  it('should deposit harvest and withdraw - once', async () => {
    const depositAmount = 40000;
    const usdcToDeposit = hre.ethers.utils.parseUnits(depositAmount.toString(), 6);
    console.log(`Deposit amount: ${depositAmount}`);
    const ppsList = await depositHarvestAndWithdraw(usdcToDeposit);
    console.log(ppsList);
  });
});

