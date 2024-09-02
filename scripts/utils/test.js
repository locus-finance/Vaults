const hre = require("hardhat");
const ethers = require("ethers");
const {
  impersonateAccount,
} = require("@nomicfoundation/hardhat-network-helpers");
const ABI = [
  "function harvest() external",

  "function balanceOf(address) external view returns(uint256)",
  "function estimatedTotalAssets() external view returns(uint256)",
  "function setSlippage(uint256) external",

  "function depositLimit() external view returns(uint256)",
  "function transferOwnership(address) external",
  "function CONVEX() external view returns(address)",
  "function strategies(address) external view returns(StrategyParams memory)",
  "function pricePerShare() external view returns(uint256)",
];
const ABI_VAULT = [
  "function deposit(uint256) external",
  "function withdraw(uint256,address,uint256) external",
];

require("dotenv").config();

const { DEPLOYER_PRIVATE_KEY, ARBITRUM_NODE, ETH_NODE } = process.env;

async function main() {
  const provider = await getProvider(true, "");
  const harvesterAddress = "0xC1287e8e489e990b424299376f37c83CD39Bfc4c";

  await impersonateAccount(harvesterAddress);
  const harvester = await hre.ethers.getSigner(harvesterAddress);
  const upgraderAddress = "0x942f39555D430eFB3230dD9e5b86939EFf185f0A";
  const strategyAddress = "0xa7eb4efe088A3618C9BA21e1520E0c8460b42D37";
  const vaultAddress = "0xF8F045583580C4Ba954CD911a8b161FafD89A9EF";
  const strategyName = "GNSStrategy";

  const targetStrategy = await hre.ethers.getContractAt(
    strategyName,
    strategyAddress,
    harvester
  );
  const vault = await hre.ethers.getContractAt("OnChainVault", vaultAddress);
  // await sendNativeTo(upgraderAddress);
  await sendNativeTo(harvesterAddress);
  // await upgradeLocalStrategy(
  //   strategyName,
  //   strategyAddress,
  //   upgraderAddress,
  //   vaultAddress
  // );

  console.log(await targetStrategy.estimatedTotalAssets());
  console.log(await vault.pricePerShare());
  console.log(await vault.totalIdle());
  console.log(await targetStrategy.harvest());
  console.log(await targetStrategy.estimatedTotalAssets());
  console.log(await vault.pricePerShare());
  console.log(await vault.totalIdle());

  // await hre.run("verify:verify", {
  //   address: "0xB0a66dD3B92293E5DC946B47922C6Ca9De464649",
  // });
}

async function sendNativeTo(to) {
  const sigs = await hre.ethers.getSigners();
  // const provider = await getProvider(true, "");
  const tx2 = await sigs[0].sendTransaction({
    to: to,
    value: hre.ethers.parseEther("100"),
  });
}

async function getProvider(isLocal, rpcUrl) {
  switch (isLocal) {
    case true:
      return new hre.ethers.JsonRpcProvider("http://127.0.0.1:8545/");
    case false:
      return new hre.ethers.JsonRpcProvider(rpcUrl || "");

    default:
      break;
  }
}

async function upgradeRealStrategy(
  entityName,
  RPC_URL,
  entityAddress,
  vaultAddress
) {
  console.log(RPC_URL);
  const provider = await getProvider(false, RPC_URL);
  console.log(provider);
  const wallet = new ethers.Wallet(DEPLOYER_PRIVATE_KEY, provider);

  const vault = await hre.ethers.getContractFactory(entityName, wallet);
  const upgraded = await hre.upgrades.upgradeProxy(entityAddress, vault, {
    unsafeAllow: ["constructor"],
    constructorArgs: [vaultAddress],
  });

  console.log(
    "Successfully upgraded implementation of",
    await upgraded.getAddress()
  );
}

async function upgradeLocalStrategy(
  entityName,
  entityAddress,
  impersonateAddress,
  vaultAddress
) {
  const provider = await getProvider(true, "");
  await impersonateAccount(impersonateAddress);
  const signer = await hre.ethers.getSigner(impersonateAddress);

  const vault = await hre.ethers.getContractFactory(entityName, signer);
  const upgraded = await hre.upgrades.upgradeProxy(entityAddress, vault, {
    unsafeAllow: ["constructor"],
    constructorArgs: [vaultAddress],
  });

  console.log(
    "Successfully upgraded implementation of",
    await upgraded.getAddress()
  );
}

async function upgradeLocalVault(
  entityName,
  RPC_URL,
  entityAddress,
  impersonateAddress
) {
  const provider = await getProvider(true, RPC_URL);
  await impersonateAccount(impersonateAddress);
  const signer = provider.getSigner(impersonateAddress);

  const vault = await hre.ethers.getContractFactory(entityName, signer);
  const upgraded = await hre.upgrades.upgradeProxy(entityAddress, vault);

  console.log("Successfully upgraded implementation of", upgraded.address);
}

async function upgradeRealVault(entityName, RPC_URL, entityAddress) {
  const provider = await getProvider(false, RPC_URL);

  const wallet = new hre.ethers.Wallet(DEPLOYER_PRIVATE_KEY).connect(provider);

  const vault = await hre.ethers.getContractFactory(entityName, wallet);
  const upgraded = await hre.upgrades.upgradeProxy(entityAddress, vault);

  console.log("Successfully upgraded implementation of", upgraded.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
