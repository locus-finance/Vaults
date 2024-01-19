const hre = require("hardhat");
const {
  impersonateAccount
} = require("@nomicfoundation/hardhat-network-helpers");
const ABI = [
  "function harvest() external",
  "function name() external view returns (string memory)",
  "function deposit(uint256) external"
];

async function main() {
  const sigs = await hre.ethers.getSigners();
  const provider = new hre.ethers.providers.JsonRpcProvider(
    "http://127.0.0.1:8545"
  );
  await impersonateAccount("0xC0496FE72226E6463A30Cf0E0f0B5BE525262B4E")
  const buyer = await ethers.provider.getSigner(
    "0xC0496FE72226E6463A30Cf0E0f0B5BE525262B4E"
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
    "0x0CD5cda0E120F7E22516f074284e5416949882C2",
    buyer
  );
  console.log(await targetContract.name())
  console.log(await targetContract.deposit(ethers.utils.parseEther("0.0001"), {gasLimit: 30000000}));
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
