const hre = require("hardhat");

const { getEnv } = require("../../utils");

const TARGET_STRATEGY = "WmntMethStrategy";
const strategist = "0x3C2792d5Ea8f9C03e8E73738E9Ed157aeB4FeCBe"
const vaultAddress = "0xd26b740A6C69fcB314159C7f3D514776bEa52C12";

const DEPLOY_SETTINGS = {
    vaultAddress: vaultAddress,
    InitStrategy: {
        ratio: "2000",
        minDebtHarvestUsdc: "0",
        maxDebtHarvestUsdc: "1000000000000"
    },
    LendWmntStrategy: {
        ratio: "2000",
        minDebtHarvestUsdc: "0",
        maxDebtHarvestUsdc: "1000000000000",
        libraryNames: ["LendWmntStrategyLib"]
    },
    MoeWmntStrategy: {
        ratio: "2000",
        minDebtHarvestUsdc: "0",
        maxDebtHarvestUsdc: "1000000000000",
        libraryNames: ["MoeWmntStrategyLib"]
    },
    MethWethStrategy: {
        ratio: "2000",
        minDebtHarvestUsdc: "0",
        maxDebtHarvestUsdc: "1000000000000",
        libraryNames: ["MethWethStrategyLib"]
    },
    WmntMethStrategy: {
        ratio: "2000",
        minDebtHarvestUsdc: "0",
        maxDebtHarvestUsdc: "1000000000000",
        libraryNames: ["WmntMethStrategyLib"]
    }
};
const OWNABLE_ABI = ["function owner() view returns (address)"];

async function main() {
    if (!DEPLOY_SETTINGS[TARGET_STRATEGY]) {
        throw new Error(`Invalid target strategy: ${TARGET_STRATEGY}`);
    }

    const [deployer] = await ethers.getSigners();

    const { vaultAddress } = DEPLOY_SETTINGS;
    const { libraryNames, oracleWindowSize, oracleGranularity } = DEPLOY_SETTINGS[TARGET_STRATEGY];

    const Vault = await hre.ethers.getContractFactory("LocusVault");
    const vault = Vault.attach(vaultAddress);

    const libraries = {};
    if (libraryNames !== undefined) {
        console.log('Found libraries to deploy and link!');
        for (const libraryName of libraryNames) {
            const library = await hre.ethers.deployContract(libraryName);
            console.log(`Deployed library: ${libraryName} - ${library.address}`);
            libraries[libraryName] = library.address;
            await hre.run("verify:verify", {
                address: library.address
            });
        }
    } else {
        console.log("No external libraries for this strategy. Continue...");
    }

    let factoryParams;
    if (libraryNames !== undefined) {
        factoryParams = {
            signer: deployer,
            libraries
        }
    } else {
        factoryParams = {
            signer: deployer
        }
    }
    const Strategy = await hre.ethers.getContractFactory(
        TARGET_STRATEGY,
        factoryParams
    );
    const strategy = await upgrades.deployProxy(
        Strategy,
        [vault.address, strategist],
        {
            initializer: "initialize",
            kind: "transparent",
            unsafeAllow: [
                "external-library-linking"
            ]
        }
    );
    await strategy.deployed();
    console.log(`Strategy deployed: ${strategy.address}`);

    const adminAddr = await hre.upgrades.erc1967.getAdminAddress(
        strategy.address
    );
    const ownableContract = await hre.ethers.getContractAt(
        OWNABLE_ABI,
        adminAddr
    );

    console.log(
        `${await strategy.name()} strategy deployed to ${strategy.address} by ${
            deployer.address
        }\n`
    );
    console.log(`Strategy proxyAdmin address: ${adminAddr}\n`);
    console.log(`proxyAdmin owner: ${await ownableContract.owner()}\n`);

    try {
        const { ratio, minDebtHarvestUsdc, maxDebtHarvestUsdc } =
            DEPLOY_SETTINGS[TARGET_STRATEGY];
        const addStrategyTx = await vault[
            "addStrategy(address,uint256,uint256,uint256,uint256)"
        ](
            strategy.address,
            Number(ratio),
            500,
            minDebtHarvestUsdc,
            maxDebtHarvestUsdc,
        );
        await addStrategyTx.wait();

        console.log(
            "Vault strategy indicators:",
            await vault.strategies(strategy.address)
        );
    } catch (e) {
        console.log(`Failed to add strategy to vault: ${e}`);
    }

    // await hre.run("verify:verify", {
    //     address: strategy.address
    // });
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
