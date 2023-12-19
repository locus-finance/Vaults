const hre = require("hardhat");
const {
  impersonateAccount
} = require("@nomicfoundation/hardhat-network-helpers");
const ABI = [
  "function harvest() external",
  "function name() external view returns (string memory)",
  "function balanceOf(address) external view returns(uint256)"
];

async function main() {
  const sigs = await hre.ethers.getSigners();
  const provider = new hre.ethers.providers.JsonRpcProvider(
    "http://127.0.0.1:8545"
  );
  await impersonateAccount("0x27f52fd2E60B1153CBD00D465F97C05245D22B82")

  // console.log(sigs[0].address);
  // console.log(await provider.getBalance(sigs[0].address));
  let wallet = new hre.ethers.Wallet(process.env.DEPLOYER_PRIVATE_KEY).connect(
    provider
  );

  // const tx2 = await sigs[0].sendTransaction({
  //   to: wallet.address,
  //   value: hre.ethers.utils.parseEther("5000"),
  // });

  // await upgradeVault();

  // const tx = await sigs[0].sendTransaction({
  //   to: "0x27f52fd2E60B1153CBD00D465F97C05245D22B82",
  //   value: hre.ethers.utils.parseEther("1000"),
  // });

  const signer = hre.ethers.provider.getSigner(
    "0x27f52fd2E60B1153CBD00D465F97C05245D22B82"
  );

  // const impersonatedSigner = await ethers.getImpersonatedSigner(
  //   "0x27f52fd2E60B1153CBD00D465F97C05245D22B82"
  // );
  const Vault = await hre.ethers.getContractFactory("OnChainVault");
  const vault = Vault.attach("0x0e86f93145d097090aCBBB8Ee44c716DACFf04d7");

  const Across = await hre.ethers.getContractFactory("AcrossStrategy");
  const strategy = Across.attach("0xDBd53985603F7E303Aaa40348906135B58c55430");

  const token = await hre.ethers.getContractAt(
    ABI,
    "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
  );
  console.log(await vault.connect(signer).name());
  console.log(await strategy.connect(signer).name());
  console.log(await vault.connect(signer).totalDebtRatio());
  console.log(await token.balanceOf(vault.address));
  console.log(await strategy.estimatedTotalAssets());
  console.log(await strategy.strategist());
  await strategy.connect(wallet).harvest();
  console.log(await token.balanceOf(vault.address));
  console.log(await strategy.balanceOfLPStaked());

  // console.log(await vault.connect(signer).owner());
  // console.log(await vault.connect(signer).governance());
  // console.log(await vault.connect(signer).management());

  // await vault.connect(signer).addStrategy(strategy.address, 400, 0, 0, ethers.utils.parseEther("10000"))

//   const Strategy = await hre.ethers.getContractFactory(
//     "AcrossStrategy",
//     wallet
// );
// const strategy = await upgrades.deployProxy(
//     Strategy,
//     [vault.address, wallet.address],
//     {
//         initializer: "initialize",
//         kind: "transparent",
//         constructorArgs: [vault.address],
//         unsafeAllow: ["constructor"],
//     }
// );
// await strategy.deployed();
console.log(strategy.address);
  // console.log(
  //   await provider.getBalance("0x27f52fd2E60B1153CBD00D465F97C05245D22B82")
  // );
  // const tx1 = await targetContract.connect(impersonatedSigner).harvest();
  // console.log(
  //   await provider.getBalance("0x27f52fd2E60B1153CBD00D465F97C05245D22B82")
  // );
}

async function upgradeVault() {
  // const abiProxy = [
  //   "function transferOwnership(address) external",
  //   "function owner() external view returns(address)",
  // ];
  // const proxy = await hre.ethers.getContractAt(
  //   abiProxy,
  //   "0x4F202835B6E12B51ef6C4ac87d610c83E9830dD9"
  // );
  // console.log(await proxy.owner());
  // const owner = await ethers.getImpersonatedSigner(
  //   "0x729F2222aaCD99619B8B660b412baE9fCEa3d90F"
  // );
  // await proxy
  //   .connect(owner)
  //   .transferOwnership("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
  // console.log(await proxy.owner());

  // const vault = await hre.ethers.getContractFactory("OnChainVault");
  // const upgraded = await hre.upgrades.upgradeProxy(
  //   "0x0e86f93145d097090acbbb8ee44c716dacff04d7",
  //   vault
  // );

  // console.log("Successfully upgraded implementation of", upgraded.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
