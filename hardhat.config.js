require('@openzeppelin/hardhat-upgrades');
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require('@nomiclabs/hardhat-truffle5');
require('@nomiclabs/hardhat-ethers');
require('hardhat-gas-reporter');
require('hardhat-log-remover');
require('hardhat-spdx-license-identifier');
require("hardhat-tracer");
require('dotenv').config();
require('solidity-coverage');

const fs = require("fs");

const updater = require('./scripts/utils/updateAddresses');

const {   DEPLOYER_PRIVATE_KEY, PROD_DEPLOYER_PRIVATE_KEY,
    } = process.env;

task("fork_reset", "Reset to local fork", async (taskArgs) => {
    await network.provider.request({
        method: "hardhat_reset",
        params: [],
    });
});

module.exports = {
    solidity: {
      compilers: [
          {
              version: "0.8.12",
              settings: {
                  optimizer: {
                      enabled: true,
                      runs: 1000000,
                  },
                  outputSelection: {
                      "*": {
                          "*": ["storageLayout"],
                      },
                  },
              },
          },

      ],
  },
    networks: {
        localhost: {
        },
        hardhat: {
            chainId: 43114,
         },
        optimismgoerli: {
             url: `https://rpc.ankr.com/optimism_testnet`,
          accounts: [`0x${DEPLOYER_PRIVATE_KEY}`]
         },
      optimism:{
        url: `https://rpc.ankr.com/optimism`,
        accounts: [`0x${PROD_DEPLOYER_PRIVATE_KEY}`]
      },
         bsctestnet: {
             url: `https://rpc.ankr.com/bsc_testnet_chapel`,
             chainId: 97,
             accounts: [`${DEPLOYER_PRIVATE_KEY}`]
         },
         polygonmumbai: {
             url: `https://rpc.ankr.com/polygon_mumbai`,
             accounts: [`${DEPLOYER_PRIVATE_KEY}`]
         },
        bsc_mainnet: {
            url: `https://bsc-dataseed.binance.org/`,
            chainId: 56,
            accounts: [`0x${DEPLOYER_PRIVATE_KEY}`]
        },
        fujiavax: {
            url: `https://rpc.ankr.com/avalanche_fuji`,
            chainId: 43113,
            accounts: [`0x${DEPLOYER_PRIVATE_KEY}`]
        },
        avalanche: {
            url: `https://api.avax.network/ext/bc/C/rpc`,
            chainId: 43114,
          accounts: [`0x${PROD_DEPLOYER_PRIVATE_KEY}`]
        },
        polygon: {
            url: `https://rpc.ankr.com/polygon`,
            chainId: 137,
            accounts: [`0x${PROD_DEPLOYER_PRIVATE_KEY}`]
        },
        arbitrum: {
            url: `https://arb1.arbitrum.io/rpc`,
            chainId: 42161,
            accounts: [`0x${PROD_DEPLOYER_PRIVATE_KEY   }`]
        },
    },
    etherscan: {
        apiKey: {
            optimisticEthereum: process.env.ETHERSCAN_API_KEY,
            optimisticGoerli:process.env.OPTIMISM_API_KEY,
            polygon: process.env.POLYGON_API_KEY,
            polygonMumbai: process.env.POLYGON_API_KEY,
            avalanche: process.env.AVAX_API_KEY,
            avalancheFujiTestnet: process.env.AVAX_API_KEY,
            bsc: process.env.BSC_API_KEY,
            bscTestnet: process.env.BSC_API_KEY,
            arbitrumOne: process.env.ARBITRUM_API_KEY
        }
  },
    gasReporter: {
    enable: true,
    currency: 'USD',
  },
    spdxLicenseIdentifier: {
        overwrite: false,
        runOnCompile: true,
    }
};


function getSortedFiles(dependenciesGraph) {
    const tsort = require("tsort")
    const graph = tsort()

    const filesMap = {}
    const resolvedFiles = dependenciesGraph.getResolvedFiles()
    resolvedFiles.forEach((f) => (filesMap[f.sourceName] = f))

    for (const [from, deps] of dependenciesGraph.entries()) {
        for (const to of deps) {
            graph.add(to.sourceName, from.sourceName)
        }
    }

    const topologicalSortedNames = graph.sort()

    // If an entry has no dependency it won't be included in the graph, so we
    // add them and then dedup the array
    const withEntries = topologicalSortedNames.concat(resolvedFiles.map((f) => f.sourceName))

    const sortedNames = [...new Set(withEntries)]
    return sortedNames.map((n) => filesMap[n])
}

function getFileWithoutImports(resolvedFile) {
    const IMPORT_SOLIDITY_REGEX = /^\s*import(\s+)[\s\S]*?;\s*$/gm

    return resolvedFile.content.rawContent.replace(IMPORT_SOLIDITY_REGEX, "").trim()
}

subtask("flat:get-flattened-sources", "Returns all contracts and their dependencies flattened")
    .addOptionalParam("files", undefined, undefined, types.any)
    .addOptionalParam("output", undefined, undefined, types.string)
    .setAction(async ({ files, output }, { run }) => {
        const dependencyGraph = await run("flat:get-dependency-graph", { files })
        console.log(dependencyGraph)

        let flattened = ""

        if (dependencyGraph.getResolvedFiles().length === 0) {
            return flattened
        }

        const sortedFiles = getSortedFiles(dependencyGraph)

        let isFirst = true
        for (const file of sortedFiles) {
            if (!isFirst) {
                flattened += "\n"
            }
            flattened += `// File ${file.getVersionedName()}\n`
            flattened += `${getFileWithoutImports(file)}\n`

            isFirst = false
        }

        // Remove every line started with "// SPDX-License-Identifier:"
        flattened = flattened.replace(/SPDX-License-Identifier:/gm, "License-Identifier:")

        flattened = `// SPDX-License-Identifier: MIXED\n\n${flattened}`

        // Remove every line started with "pragma experimental ABIEncoderV2;" except the first one
        flattened = flattened.replace(/pragma experimental ABIEncoderV2;\n/gm, ((i) => (m) => (!i++ ? m : ""))(0))
        // Remove every line started with "pragma abicoder v2;" except the first one
        flattened = flattened.replace(/pragma abicoder v2;\n/gm, ((i) => (m) => (!i++ ? m : ""))(0))
        // Remove every line started with "pragma solidity ****" except the first one
        flattened = flattened.replace(/pragma solidity .*$\n/gm, ((i) => (m) => (!i++ ? m : ""))(0))


        flattened = flattened.trim()
        if (output) {
            console.log("Writing to", output)
            fs.writeFileSync(output, flattened)
            return ""
        }
        return flattened
    })

subtask("flat:get-dependency-graph")
    .addOptionalParam("files", undefined, undefined, types.any)
    .setAction(async ({ files }, { run }) => {
        const sourcePaths = files === undefined ? await run("compile:solidity:get-source-paths") : files.map((f) => fs.realpathSync(f))

        const sourceNames = await run("compile:solidity:get-source-names", {
            sourcePaths,
        })

        const dependencyGraph = await run("compile:solidity:get-dependency-graph", { sourceNames })

        return dependencyGraph
    })

task("flat", "Flattens and prints contracts and their dependencies")
    .addOptionalVariadicPositionalParam("files", "The files to flatten", undefined, types.inputFile)
    .addOptionalParam("output", "Specify the output file", undefined, types.string)
    .setAction(async ({ files, output }, { run }) => {
        console.log(
            await run("flat:get-flattened-sources", {
                files,
                output,
            })
        )
    })

task(
    "test",
    "Download addresses and run tests",
    async function (taskArguments, hre, runSuper) {
        await updater.updateAddresses().then(function() {
            return runSuper();
        });
    }
);

task("update", "Updates addresses")
    .setAction(async (taskArgs) => {
        await updater.updateAddresses();
    });
