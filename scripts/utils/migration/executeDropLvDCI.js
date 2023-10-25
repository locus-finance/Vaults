const executeDrop = require('./reusable/executeDrop');
executeDrop(
  "./scripts/utils/migration/csv/lvDciTokenHolders.csv",
  "0xf62A24EbE766d0dA04C9e2aeeCd5E86Fac049B7B"
)()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });