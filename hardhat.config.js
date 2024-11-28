require("@openzeppelin/hardhat-upgrades");
// eslint-disable-next-line node/no-extraneous-require
require("@nomiclabs/hardhat-vyper");
require("hardhat-gas-reporter");
require("dotenv").config();
require("solidity-coverage");
require("hardhat-contract-sizer");
require("hardhat-deploy");
require("@nomicfoundation/hardhat-verify");
+require("@nomicfoundation/hardhat-toolbox");

const fs = require("fs");

const {
  DEPLOYER_PRIVATE_KEY,
  PROD_DEPLOYER_PRIVATE_KEY,
  ETH_NODE,
  ETH_FORK_BLOCK,
  ARBITRUM_NODE,
} = process.env;

// require("./tasks/migration/saveDropReceiversFromMigration")(task);
// require("./tasks/migration/countDropReceiversFromMigration")(task);
// require("./tasks/migration/migrateVaults")(task);
// require("./tasks/migration/dropToVaults")(task);
// require("./tasks/migration/gatherUnmigrated")(task);
// require("./tasks/migration/finalDrop")(task);
// require("./tasks/migration/populateMigration")(task);
// require("./tasks/redeploy/generateFinalHoldersList")(task);
// require("./tasks/redeploy/calculateWantBalances")(task);
// require("./tasks/harvest/reserves")(task);

task("fork_reset", "Reset to local fork", async (taskArgs) => {
  await network.provider.request({
    method: "hardhat_reset",
    params: [],
  });
});

module.exports = {
  mocha: {
    timeout: 100000000,
  },
  solidity: {
    compilers: [
      {
        version: "0.8.23",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 10,
          },
          outputSelection: {
            "*": {
              "*": ["storageLayout"],
            },
          },
        },
      },
      {
        version: "0.8.18",
        settings: {
          optimizer: {
            enabled: true,
            runs: 5,
          },
          outputSelection: {
            "*": {
              "*": ["storageLayout"],
            },
          },
        },
      },
      {
        version: "0.6.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 5,
          },
          outputSelection: {
            "*": {
              "*": ["storageLayout"],
            },
          },
        },
      },
    ],
    overrides: {
      "contracts/strategies/arbitrum/*.sol": {
        version: "0.8.18",
      },
      "contracts/mock/arbitrum/*.sol": {
        version: "0.8.18",
      },
    },
  },
  vyper: {
    version: "0.3.3",
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
  },
  networks: {
    hardhat: {
      chainId: 42161,
      forking: {
        url: process.env.ARBITRUM_NODE || "",
        blockNumber: 231466451,
      },
      // maxPriorityFeePerGas: 2000000000,
      // allowUnlimitedContractSize: true,
    },
    mainnet: {
      url: ETH_NODE || "",
      chainId: 1,
      accounts: [`0x${PROD_DEPLOYER_PRIVATE_KEY || ""}`],
    },
    optimismgoerli: {
      url: `https://rpc.ankr.com/optimism_testnet`,
      accounts: [`0x${DEPLOYER_PRIVATE_KEY || ""}`],
    },
    sepolia: {
      url: `https://rpc.ankr.com/eth_sepolia`,
      accounts: [`0x${DEPLOYER_PRIVATE_KEY || ""}`],
    },
    optimism: {
      url: `https://rpc.ankr.com/optimism`,
      accounts: [`0x${PROD_DEPLOYER_PRIVATE_KEY || ""}`],
    },
    bsctestnet: {
      url: `https://rpc.ankr.com/bsc_testnet_chapel`,
      chainId: 97,
      accounts: [`${DEPLOYER_PRIVATE_KEY || ""}`],
    },
    polygonmumbai: {
      url: `https://rpc.ankr.com/polygon_mumbai`,
      accounts: [`${DEPLOYER_PRIVATE_KEY || ""}`],
    },
    bsc_mainnet: {
      url: `https://bsc-dataseed.binance.org/`,
      chainId: 56,
      accounts: [`0x${DEPLOYER_PRIVATE_KEY || ""}`],
    },
    fujiavax: {
      url: `https://rpc.ankr.com/avalanche_fuji`,
      chainId: 43113,
      accounts: [`0x${DEPLOYER_PRIVATE_KEY || ""}`],
    },
    avalanche: {
      url: `https://api.avax.network/ext/bc/C/rpc`,
      chainId: 43114,
      accounts: [`0x${PROD_DEPLOYER_PRIVATE_KEY || ""}`],
    },
    polygon: {
      url: `https://rpc.ankr.com/polygon`,
      chainId: 137,
      accounts: [`0x${PROD_DEPLOYER_PRIVATE_KEY || ""}`],
    },
    arbitrumOne: {
      url: ARBITRUM_NODE || "",
      chainId: 42161,
      accounts: [`0x${PROD_DEPLOYER_PRIVATE_KEY || ""}`],
    },
    mantle: {
      url: "https://rpc.mantle.xyz/",
      chainId: 5000,
      accounts: [`0x${PROD_DEPLOYER_PRIVATE_KEY}`],
    },
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY || "",
      sepolia: process.env.ETHERSCAN_API_KEY,
      arbitrumOne: process.env.ARBISCAN_API_KEY,
      mantle: process.env.ETHERSCAN_API_KEY,
    },
    customChains: [
      {
        network: "mantle",
        chainId: 5000,
        urls: {
          apiURL: "https://explorer.mantle.xyz/api",
          browserURL: "https://explorer.mantle.xyz/",
        },
      },
    ],
  },
  gasReporter: {
    enable: true,
    currency: "USD",
  },
  spdxLicenseIdentifier: {
    overwrite: false,
    runOnCompile: true,
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: true,
    strict: false,
  },
  tracer: {
    gasCost: false,
  },
  abiExporter: {
    path: "./abi",
    runOnCompile: true,
    clear: true,
    flat: true,
    spacing: 2,
    format: "minimal",
    only: [
      ":Vault$",
      ":TestStrategy$",
      ":AuraBALStrategy$",
      "AuraTriPoolStrategy$",
      ":AuraWETHStrategy$",
      ":CVXStrategy$",
      "GMDStrategy$",
      "GMXStrategy$",
      "GNSStrategy$",
      "JOEStrategy$",
      ":FraxStrategy$",
      ":FXSStrategy$",
      ":LidoAuraStrategy$",
      ":RocketAuraStrategy$",
      ":YCRVStrategy$",
    ],
  },
};

function getSortedFiles(dependenciesGraph) {
  const tsort = require("tsort");
  const graph = tsort();

  const filesMap = {};
  const resolvedFiles = dependenciesGraph.getResolvedFiles();
  resolvedFiles.forEach((f) => (filesMap[f.sourceName] = f));

  for (const [from, deps] of dependenciesGraph.entries()) {
    for (const to of deps) {
      graph.add(to.sourceName, from.sourceName);
    }
  }

  const topologicalSortedNames = graph.sort();

  // If an entry has no dependency it won't be included in the graph, so we
  // add them and then dedup the array
  const withEntries = topologicalSortedNames.concat(
    resolvedFiles.map((f) => f.sourceName)
  );

  const sortedNames = [...new Set(withEntries)];
  return sortedNames.map((n) => filesMap[n]);
}

function getFileWithoutImports(resolvedFile) {
  const IMPORT_SOLIDITY_REGEX = /^\s*import(\s+)[\s\S]*?;\s*$/gm;

  return resolvedFile.content.rawContent
    .replace(IMPORT_SOLIDITY_REGEX, "")
    .trim();
}

subtask(
  "flat:get-flattened-sources",
  "Returns all contracts and their dependencies flattened"
)
  .addOptionalParam("files", undefined, undefined, types.any)
  .addOptionalParam("output", undefined, undefined, types.string)
  .setAction(async ({ files, output }, { run }) => {
    const dependencyGraph = await run("flat:get-dependency-graph", {
      files,
    });

    let flattened = "";

    if (dependencyGraph.getResolvedFiles().length === 0) {
      return flattened;
    }

    const sortedFiles = getSortedFiles(dependencyGraph);

    let isFirst = true;
    for (const file of sortedFiles) {
      if (!isFirst) {
        flattened += "\n";
      }
      flattened += `// File ${file.getVersionedName()}\n`;
      flattened += `${getFileWithoutImports(file)}\n`;

      isFirst = false;
    }

    // Remove every line started with "pragma experimental ABIEncoderV2;" except the first one
    flattened = flattened.replace(
      /pragma experimental ABIEncoderV2;\n/gm,
      (
        (i) => (m) =>
          !i++ ? m : ""
      )(0)
    );
    // Remove every line started with "pragma abicoder v2;" except the first one
    flattened = flattened.replace(
      /pragma abicoder v2;\n/gm,
      (
        (i) => (m) =>
          !i++ ? m : ""
      )(0)
    );
    // Remove every line started with "pragma solidity ****" except the first one
    flattened = flattened.replace(
      /pragma solidity .*$\n/gm,
      (
        (i) => (m) =>
          !i++ ? m : ""
      )(0)
    );

    flattened = flattened.trim();
    if (output) {
      console.log("Writing to", output);
      fs.writeFileSync(output, flattened);
      return "";
    }
    return flattened;
  });

subtask("flat:get-dependency-graph")
  .addOptionalParam("files", undefined, undefined, types.any)
  .setAction(async ({ files }, { run }) => {
    const sourcePaths =
      files === undefined
        ? await run("compile:solidity:get-source-paths")
        : files.map((f) => fs.realpathSync(f));

    const sourceNames = await run("compile:solidity:get-source-names", {
      sourcePaths,
    });

    const dependencyGraph = await run("compile:solidity:get-dependency-graph", {
      sourceNames,
    });

    return dependencyGraph;
  });

task("flat", "Flattens and prints contracts and their dependencies")
  .addOptionalVariadicPositionalParam(
    "files",
    "The files to flatten",
    undefined,
    types.inputFile
  )
  .addOptionalParam(
    "output",
    "Specify the output file",
    undefined,
    types.string
  )
  .setAction(async ({ files, output }, { run }) => {
    console.log(
      await run("flat:get-flattened-sources", {
        files,
        output,
      })
    );
  });

// subtask("compile:vyper:get-source-names").setAction(async (_, __, runSuper) => {
//   const paths = await runSuper();
//   paths.push("lib/yearn-vaults/contracts/Vault.vy");
//   return paths;
// });

// subtask("compile:solidity:transform-import-name").setAction(
//   async ({ importName }, _hre, runSuper) => {
//     const remappings = { "@yearn-protocol/": "lib/yearn-vaults/" };
//     for (const [from, to] of Object.entries(remappings)) {
//       if (importName.startsWith(from) && !importName.startsWith(".")) {
//         return importName.replace(from, to);
//       }
//     }
//     return importName;
//   }
// );

subtask("compile:solidity:get-compilation-job-for-file").setAction(
  async ({ dependencyGraph, file }, _hre, runSuper) => {
    const job = await runSuper({ dependencyGraph, file });
    if ("reason" in job) return job;
    const remappings = { "@yearn-protocol/": "lib/yearn-vaults/" };
    job.getSolcConfig().settings.remappings = Object.entries(remappings).map(
      ([from, to]) => `${from}=${to}`
    );
    return job;
  }
);
