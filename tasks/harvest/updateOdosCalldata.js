const axios = require("axios");
module.exports = (task) =>
  task(
    "odos",
    "Calculates calldata for ODOS Router.",
  )
    .addOptionalParam('strategy', "Define strategy address.", '', types.string)
    .addOptionalParam('tokenFrom', "Define an input token.", '', types.string)
    .addOptionalParam('tokenTo', "Define a output token.", '', types.string)
    .addOptionalParam('amount', "Define an amount of input tokens to be swapped.", '', types.string)
    .addOptionalParam('slippage', "Define slippage in percents", 0.3, types.float)
    .setAction(async ({ strategy, tokenFrom, tokenTo, amount, slippage }, hre) => {
        const strategyInstance = await hre.ethers.getContractAt(
            "OdosStrategyHelper",
            strategy
        );
        // call to update the requests on calldata calculation
        // parse the requests
        // perform the calculations
        // past the results into the LocusDataFeed
    });