# Locus Finance Vault smart contracts

This project is a fork of Yearn Vault with custom strategies.

```shell
git submodule update --init --recursive
npm install
cp env.template .env
nano .env
npx hardhat test
node scripts/Vault.js
```
## Deploy new Vault

Vault settings can be configured in `scripts/deploy/<vault name>/Vault.js`. 

Customizable options:
* want token address in `const *_ADDRESS`
* want token decimals in `const *_DECIMALS`
* name in `DEPLOY_SETTINGS`
* symbol in `DEPLOY_SETTINGS`
* deposit limit in `DEPLOY_SETTINGS` (defined in want tokens)

After configuration vault can be deployed with following command. `GOVERNANCE_ACCOUNT` and `TREASURY_ACCOUNT` passed using environment variables.

```
GOVERNANCE_ACCOUNT="" TREASURY_ACCOUNT="" npx hardhat run scripts/deploy/<vault name>/Vault.js --network <hardhat.config.js network>
```
Deployer account is configured in `hardhat.config.js` networks.

## Deploy new Strategy

Strategy settings can be configured in `scripts/deploy/<vault name>/Strategy.js`. 

Customizable options:
* ratio (100% = 10000)
* minDebtHarvest
* maxDebtHarvest

After configuration strategy can be deployed with following command. `TARGET_STRATEGY` and `<vault name>_ADDRESS` (e.g. VETH_ADDRESS) passed using environment variables.

```
TARGET_STRATEGY="" <vault name>_ADDRESS="" npx hardhat run scripts/deploy/<vault name>/Strategy.js --network <hardhat.config.js network>

TARGET_STRATEGY="RocketAuraStrategy" VETH_ADDRESS="0x3edbE670D03C4A71367dedA78E73EA4f8d68F2E4" npx hardhat run scripts/deploy/vETH/Strategy.js --network mainnet

TARGET_STRATEGY="FraxStrategy" VETH_ADDRESS="0x3edbE670D03C4A71367dedA78E73EA4f8d68F2E4" npx hardhat run scripts/deploy/vETH/Strategy.js --network mainnet

TARGET_STRATEGY="LidoAuraStrategy" VETH_ADDRESS="0x3edbE670D03C4A71367dedA78E73EA4f8d68F2E4" npx hardhat run scripts/deploy/vETH/Strategy.js --network mainnet

TARGET_STRATEGY="AuraBALStrategy" DVAULT_ADDRESS="0xf62A24EbE766d0dA04C9e2aeeCd5E86Fac049B7B" npx hardhat run scripts/deploy/lvDCI/Strategy.js --network mainnet

TARGET_STRATEGY="AuraWETHStrategy" DVAULT_ADDRESS="0xf62A24EbE766d0dA04C9e2aeeCd5E86Fac049B7B" npx hardhat run scripts/deploy/lvDCI/Strategy.js --network mainnet

TARGET_STRATEGY="CVXStrategy" DVAULT_ADDRESS="0xf62A24EbE766d0dA04C9e2aeeCd5E86Fac049B7B" npx hardhat run scripts/deploy/lvDCI/Strategy.js --network mainnet

TARGET_STRATEGY="FXSStrategy" DVAULT_ADDRESS="0xf62A24EbE766d0dA04C9e2aeeCd5E86Fac049B7B" npx hardhat run scripts/deploy/lvDCI/Strategy.js --network mainnet

TARGET_STRATEGY="YCRVStrategy" DVAULT_ADDRESS="0xf62A24EbE766d0dA04C9e2aeeCd5E86Fac049B7B" npx hardhat run scripts/deploy/lvDCI/Strategy.js --network mainnet

TARGET_STRATEGY="GMXStrategy" lvAYI_ADDRESS="0x0f094f6deb056af1fa1299168188fd8c78542a07" npx hardhat run scripts/deploy/lvAYI/Strategy.js --network arbitrumOne

TARGET_STRATEGY="GNSStrategy" lvAYI_ADDRESS="0x0f094f6deb056af1fa1299168188fd8c78542a07" npx hardhat run scripts/deploy/lvAYI/Strategy.js --network arbitrumOne

TARGET_STRATEGY="JOEStrategy" lvAYI_ADDRESS="0x0f094f6deb056af1fa1299168188fd8c78542a07" npx hardhat run scripts/deploy/lvAYI/Strategy.js --network arbitrumOne
```
