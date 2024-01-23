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
  "function withdraw(uint256,address,uint256) external"
];

async function main() {
  const sigs = await hre.ethers.getSigners();
  const provider = new hre.ethers.providers.JsonRpcProvider(
    "http://127.0.0.1:8545"
  );
  await impersonateAccount("0x942f39555D430eFB3230dD9e5b86939EFf185f0A")
  const harvester = await ethers.provider.getSigner(
    "0x942f39555D430eFB3230dD9e5b86939EFf185f0A"
  );

  await impersonateAccount("0xC1287e8e489e990b424299376f37c83CD39Bfc4c")
  const strat = await ethers.provider.getSigner(
    "0xC1287e8e489e990b424299376f37c83CD39Bfc4c"
  );

  await impersonateAccount("0xD6153F5af5679a75cC85D8974463545181f48772")
  const buyer = await ethers.provider.getSigner(
    "0xD6153F5af5679a75cC85D8974463545181f48772"
  );

  // console.log(sigs[0].address);
  // console.log(await provider.getBalance(sigs[0].address));
  // let wallet = new hre.ethers.Wallet(process.env.DEPLOYER_PRIVATE_KEY).connect(
  //   provider
  // );
    console.log(buyer._address);
  const tx2 = await sigs[0].sendTransaction({
    to: buyer._address,
    value: hre.ethers.utils.parseEther("100"),
  });
  await tx2.wait();

  const tx3 = await sigs[0].sendTransaction({
    to: harvester._address,
    value: hre.ethers.utils.parseEther("100"),
  });
  await tx3.wait();
  const tx4 = await sigs[0].sendTransaction({
    to: harvester._address,
    value: hre.ethers.utils.parseEther("100"),
  });
  await tx4.wait();

  // await upgradeVault();

  // const tx = await sigs[0].sendTransaction({
  //   to: "0x27f52fd2E60B1153CBD00D465F97C05245D22B82",
  //   value: hre.ethers.utils.parseEther("1000"),
  // });

  // const signer = hre.ethers.provider.getSigner(
  //   "0x27f52fd2E60B1153CBD00D465F97C05245D22B82"
  // );

  // const impersonatedSigner = await ethers.getImpersonatedSigner(
  //   "0x27f52fd2E60B1153CBD00D465F97C05245D22B82"
  // );

  const targetContract = await hre.ethers.getContractAt(
    ABI,
    "0xB0a66dD3B92293E5DC946B47922C6Ca9De464649",
    buyer
  );

  const want = await hre.ethers.getContractAt(
    ABI,
    "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    buyer
  );

  const strategyA = await hre.ethers.getContractAt(
    ABI,
    "0x854F178112008143014ECffd4059e3f913a47B40",
    harvester
  );

  const strategyB = await hre.ethers.getContractAt(
    ABI,
    "0x854F178112008143014ECffd4059e3f913a47B40",
    harvester
  );
    // await want.connect(buyer).approve(targetContract.address, ethers.utils.parseEther("100000000000"))

  console.log(await targetContract.name())
  // console.log("DEPOSIT");
  // console.log("Before", await want.balanceOf(targetContract.address));

  // await targetContract.deposit(ethers.utils.parseEther("0.00000001"), {gasLimit: 30000000});
  // console.log("After",await want.balanceOf(targetContract.address));
  // await strategyA.connect(strat).setSlippage(9950)
  await strategyB.connect(strat).setSlippage(9950)
  // console.log("HARVEST CVX");
  // console.log("ETA b ", await strategyA.estimatedTotalAssets())
  // await strategyA.harvest();
  // console.log("ETA a ", await strategyA.estimatedTotalAssets())
  // console.log("HARVEST YCRV");
  // console.log("ETA b ", await strategyB.estimatedTotalAssets())
  await strategyB.harvest();
  // console.log("ETA a ", await strategyB.estimatedTotalAssets())
// console.log("WITHDRAW");
//   console.log("ETA b ", await strategyB.estimatedTotalAssets())
//   console.log("ETA b ", await strategyA.estimatedTotalAssets())
//   console.log("Before", await want.balanceOf(buyer._address));


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

  const vault = await hre.ethers.getContractFactory("OnChainVault");
  const upgraded = await hre.upgrades.upgradeProxy(
    "0x0e86f93145d097090acbbb8ee44c716dacff04d7",
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
