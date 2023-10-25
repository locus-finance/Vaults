const executeDrop = require('./reusable/executeDrop');
executeDrop(
  "./scripts/utils/migration/csv/lvDciTokenHolders.csv",
  "0x3edbE670D03C4A71367dedA78E73EA4f8d68F2E4"
)()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });