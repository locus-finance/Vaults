const axios = require("axios");
module.exports = (task) =>
  task(
    "reserves",
    "Getting the reserves of UniswapV2 pool.",
  )
    .addOptionalParam('pair', "Define an address of the pair.", '0xc1f43E45F86E7bfb92C3c309b0eF366F9Ba33Bfa', types.string)
    .setAction(async ({ pair }, hre) => {
        const pairInstance = await hre.ethers.getContractAt(
            "IMoePair",
            pair
        );
        const reserves = await pairInstance.getReserves();
        const token0Instance = await hre.ethers.getContractAt(
          "IERC20Metadata",
          await pairInstance.token0()
        );
        const token1Instance = await hre.ethers.getContractAt(
          "IERC20Metadata",
          await pairInstance.token1()
        );
        console.log(`Acquired reserves:\nReserve 0 (${await token0Instance.symbol()}) - ${reserves.reserve0.toString()}\nReserve 1 (${await token1Instance.symbol()}) - ${reserves.reserve1.toString()}`);
    });