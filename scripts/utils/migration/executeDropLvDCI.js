const executeDrop = require('./reusable/executeDrop');
executeDrop(
  "./scripts/utils/migration/csv/lvDciTokenHolders.csv"
)()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });