const calculateInjectableValues = require('./reusable/calculateInjectableValues');
calculateInjectableValues(
  "0x3edbE670D03C4A71367dedA78E73EA4f8d68F2E4",
  parseInt(process.env.ETH_FORK_BLOCK)
)()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });