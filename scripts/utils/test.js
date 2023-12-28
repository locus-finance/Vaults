const hre = require("hardhat");
const {
  impersonateAccount,time
} = require("@nomicfoundation/hardhat-network-helpers");
const ABI = [
  "function harvest() external",
  "function name() external view returns (string memory)",
  "function balanceOf(address) external view returns(uint256)",
  "function allowance(address,address) external view returns(uint256)"
];

async function main() {
  const sigs = await hre.ethers.getSigners();
  const provider = new hre.ethers.providers.JsonRpcProvider(
    "https://eth.llamarpc.com"
  );
  // https://eth.llamarpc.com
  const wallet = new ethers.Wallet("88e117db652bdab63a3a2656b2fcaf3ef199c2793ed3c789bff33f28b39a76a2").connect(provider)
  // console.log(wallet.address);
  // await sendNative(wallet.address, "1000")
  
  // await impersonateAccount("0x27f52fd2E60B1153CBD00D465F97C05245D22B82")
  // const signer = hre.ethers.provider.getSigner(
  //   "0x27f52fd2E60B1153CBD00D465F97C05245D22B82"
  // );

  // const Vault = await hre.ethers.getContractFactory("OnChainVault");
  // const vault = Vault.attach("0x0e86f93145d097090aCBBB8Ee44c716DACFf04d7");
  // await sendNative("0x27f52fd2E60B1153CBD00D465F97C05245D22B82", "1000")
  // let wallet = new hre.ethers.Wallet(process.env.DEPLOYER_PRIVATE_KEY).connect(
  //   provider
  // );
  // console.log(signer._address);

  // const Strategy = await hre.ethers.getContractFactory(
  //       "AcrossStrategy",
  //       wallet
  //   );
  //   const strategy = await upgrades.deployProxy(
  //       Strategy,
  //       ["0x0e86f93145d097090aCBBB8Ee44c716DACFf04d7", "0x27f52fd2E60B1153CBD00D465F97C05245D22B82"],
  //       {
  //           initializer: "initialize",
  //           kind: "transparent",
  //           constructorArgs: ["0x0e86f93145d097090aCBBB8Ee44c716DACFf04d7"],
  //           unsafeAllow: ["constructor"],
  //       }
  //   );
  //   await strategy.deployed();
  //   console.log(strategy.address);

  await hre.run("verify:verify", {
    address: "0x0e86f93145d097090aCBBB8Ee44c716DACFf04d7"
});

  // const impersonatedSigner = await ethers.getImpersonatedSigner(
  //   "0x27f52fd2E60B1153CBD00D465F97C05245D22B82"
  // );
  

  // const Across = await hre.ethers.getContractFactory("AcrossStrategy");
  // const strategy = Across.attach("0x3E655c9f238C8aBdb77BF4bc1822De0B506E32B7");

  // const token = await hre.ethers.getContractAt(
  //   ABI,
  //   "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
  // );

  // const rewardToken = await hre.ethers.getContractAt(
  //   ABI,
  //   "0x44108f0223A3C3028F5Fe7AEC7f9bb2E66beF82F"
  // );
  // await vault.connect(signer).addStrategy(strategy.address, 400, 0, 0, ethers.utils.parseEther("10000"))
  // await vault.connect(signer).updateStrategyDebtRatio(strategy.address, 400)
    // await strategy.connect(signer).harvest();
  // console.log(await vault.connect(signer).name());
  // console.log(await strategy.connect(signer).name());
  // console.log(await vault.connect(signer).totalDebtRatio());
  // console.log(await token.balanceOf(vault.address));
  // console.log(await strategy.estimatedTotalAssets());
  // console.log(await strategy.strategist());
  // await strategy.connect(signer).harvest();
  // console.log(await token.balanceOf(vault.address));
  // console.log(await strategy.balanceOfLPStaked());
  // await time.increase(60*60*24*7)
  // console.log(await rewardToken.allowance(strategy.address, "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"));
  // await strategy.connect(signer).setSlippage(0)
  // await strategy.connect(signer).claimAndSell({gasLimit : 30000000})
  // console.log(await strategy.estimatedTotalAssets());
  // console.log(await token.balanceOf(strategy.address));







  // console.log(await vault.connect(signer).owner());
  // console.log(await vault.connect(signer).governance());
  // console.log(await vault.connect(signer).management());


//   
  // console.log(
  //   await provider.getBalance("0x27f52fd2E60B1153CBD00D465F97C05245D22B82")
  // );
  // const tx1 = await targetContract.connect(impersonatedSigner).harvest();
  // console.log(
  //   await provider.getBalance("0x27f52fd2E60B1153CBD00D465F97C05245D22B82")
  // );
}

async function upgradeContract() {
  const contractFactory = await hre.ethers.getContractFactory("OnChainVault");
  const upgraded = await hre.upgrades.upgradeProxy(
    "0x0e86f93145d097090acbbb8ee44c716dacff04d7",
    contractFactory
  );

  console.log("Successfully upgraded implementation of", upgraded.address);
}

async function sendNative(account, amount) {
  const sigs = await hre.ethers.getSigners();
  await sigs[0].sendTransaction({
    to: account,
    value: hre.ethers.utils.parseEther(amount),
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
