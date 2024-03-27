const hre = require("hardhat");
const {
  impersonateAccount
} = require("@nomicfoundation/hardhat-network-helpers");
const ABI = [
  "function harvest() external",
  "function name() external view returns (string memory)",
  "function deposit(uint256) external",
  "function approve(address,uint256) external",
  "function balanceOf(address) external view returns(uint256)",
  "function estimatedTotalAssets() external view returns(uint256)",
  "function setSlippage(uint256) external",
  "function withdraw(uint256,address,uint256) external",
  "function depositLimit() external view returns(uint256)",
  "function transferOwnership(address) external",
  "function CONVEX() external view returns(address)"
];

require("dotenv").config();

const {
  DEPLOYER_PRIVATE_KEY,
  ARBITRUM_NODE,
  ETH_NODE
} = process.env;

async function main() {
  // const sigs = await hre.ethers.getSigners();
  const provider = new hre.ethers.providers.JsonRpcProvider(
    "http://127.0.0.1:8545/" || ""
  );
  await impersonateAccount("0xB232b6791d83fCe7a99222c63a525c88c227A53D")
  const signer = await ethers.provider.getSigner(
    "0xB232b6791d83fCe7a99222c63a525c88c227A53D"
  );

  // console.log(sigs[0].address);
  // console.log(await provider.getBalance(sigs[0].address));
  // let wallet = new hre.ethers.Wallet(process.env.DEPLOYER_PRIVATE_KEY).connect(
  //   provider
  // );
  //   console.log(signer._address);
  // const tx2 = await sigs[0].sendTransaction({
  //   to: wallet.address,
  //   value: hre.ethers.utils.parseEther("100"),
  // });
  // await tx2.wait();

  await upgradeVault();

  const targetContract = await hre.ethers.getContractAt(
    ABI,
    "",
    provider
  );
  console.log(await targetContract.connect(signer).name());
  console.log(await targetContract.connect(signer).withdraw(2000000, "0xB232b6791d83fCe7a99222c63a525c88c227A53D", 5000));

  // const want = await hre.ethers.getContractAt(
  //   ABI,
  //   "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
  //   wallet
  // );
  // const vaultAddress = "0x0CD5cda0E120F7E22516f074284e5416949882C2"
  // const strategist = "0xC1287e8e489e990b424299376f37c83CD39Bfc4c"

  // const OriginStrategy = await ethers.getContractFactory("OriginEthStrategy");
  //     const strategy = await upgrades.deployProxy(
  //       OriginStrategy,
  //       [vaultAddress, strategist],
  //       {
  //         kind: "uups",
  //         unsafeAllow: ["constructor"],
  //         constructorArgs: [vaultAddress],
  //       }
  //     );
  //     await strategy.deployed();
  //     await hre.run("verify:verify", {
  //       address: strategy.address,
  //       constructorArguments: [vaultAddress],
  //   });
  // await want.connect(wallet).approve(targetContract.address, ethers.utils.parseEther("100000000000"))
// console.log(await want.balanceOf(wallet.address));
//   console.log(await targetContract.name())
//   console.log(await targetContract.depositLimit())
  // console.log("DEPOSIT");
  // console.log("Before", await want.balanceOf(targetContract.address));

  // await targetContract.deposit(ethers.utils.parseEther("0.000000000001"),{gasLimit: 30000000});
  
    // await targetContract.connect(buyer).approve(targetContract.address, ethers.utils.parseEther("100000000000"))

  // await targetContract.withdraw(await targetContract.balanceOf(buyer._address), buyer._address, 9000)
  // console.log("After", await want.balanceOf(buyer._address));

  // console.log("ETA a ", await strategyB.estimatedTotalAssets())
  // console.log("ETA a ", await strategyA.estimatedTotalAssets())


  // console.log(await targetContract.connect(signer).name());
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

  const provider = new ethers.JsonRpcProvider(
    "http://127.0.0.1:8545"
  );
  await impersonateAccount("0x942f39555D430eFB3230dD9e5b86939EFf185f0A")

  // console.log("upgrading");
  const owner = await ethers.provider.getSigner(
    "0x942f39555D430eFB3230dD9e5b86939EFf185f0A"
  );

  const vault = await hre.ethers.getContractFactory("OnChainVault");
  const upgraded = await hre.upgrades.upgradeProxy(
    "0x6318938F825F57d439B3a9E25C38F04EF97987D8",
    vault
  );

  console.log("Successfully upgraded implementation of", upgraded.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
