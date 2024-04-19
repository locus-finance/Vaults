const { ethers, upgrades } = require("hardhat");

async function main() {
  const { deployer } = await getNamedAccounts();

  console.log(`Your address: ${deployer}. Network: ${hre.network.name}`);

  const mantleUSDC = "0x09Bc4E0D864854c6aFB6eB9A9cdF58aC190D0dF9";
  const treasury = "0xf4bEC3e032590347Fc36AD40152C7155f8361d39"
  const strategist = "0x3C2792d5Ea8f9C03e8E73738E9Ed157aeB4FeCBe"

  const Vault = await ethers.getContractFactory("LocusVault");
  const vault = await upgrades.deployProxy(
    Vault,
    [
      mantleUSDC,
      strategist,
      treasury
    ],
    {
      initializer: "initialize",
      kind: "uups",
    }
  );
  await vault.deployed();

  await hre.run("verify:verify", {
    address: vault.address,
  });

  const VaultToken = await ethers.getContractFactory("LocusVaultToken");
  const vaultToken = await upgrades.deployProxy(
    VaultToken,
    [
      strategist,
      vault.address,
      "Locus Mantle Vault",
      "xMNT",
    ],
    {
      initializer: "initialize",
      kind: "uups",
    }
  );
  await vaultToken.deployed();

  console.log("VaultToken deployed to:", vaultToken.address);

  await hre.run("verify:verify", {
    address: vaultToken.address,
  });

  const setVaultTokenTx = await vault.setVaultToken(vaultToken.address);
  await setVaultTokenTx.wait();
  console.log(`Vault token is set:\n${setVaultTokenTx}`);
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });