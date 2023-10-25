const calculateInjectableValues = require('./reusable/calculateInjectableValues');
calculateInjectableValues(
  "0xf62A24EbE766d0dA04C9e2aeeCd5E86Fac049B7B",
  parseInt(process.env.ETH_FORK_BLOCK)
)()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });