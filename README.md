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
Deployer account is configuring in `hardhat.config.js` networks.

## Deploy new Strategy

Strategy settings can be configured in `scripts/deploy/<vault name>/Strategy.js`. 

Customizable options:
* ratio (100% = 10000)
* minDebtHarvest
* maxDebtHarvest

After configuration strategy can be deployed with following command. `TARGET_STRATEGY` and `<vault name>_ADDRESS` (e.g. VETH_ADDRESS) passed using environment variables.

```
TARGET_STRATEGY="" <vault name>_ADDRESS="" npx hardhat run scripts/deploy/<vault name>/Strategy.js --network <hardhat.config.js network>

TARGET_STRATEGY="RocketAuraStrategy" VETH_ADDRESS="0xE2fb9fBEadFc3577584C60A2f7FDF9933abed81a" npx hardhat run scripts/deploy/vETH/Strategy.js --network mainnet

TARGET_STRATEGY="FraxStrategy" VETH_ADDRESS="0xE2fb9fBEadFc3577584C60A2f7FDF9933abed81a" npx hardhat run scripts/deploy/vETH/Strategy.js --network mainnet

TARGET_STRATEGY="LidoAuraStrategy" VETH_ADDRESS="0xE2fb9fBEadFc3577584C60A2f7FDF9933abed81a" npx hardhat run scripts/deploy/vETH/Strategy.js --network mainnet

TARGET_STRATEGY="AuraBALStrategy" DVAULT_ADDRESS="0xebac2E85E95c67ac0baDC4dEFb58708De8F5C39b" npx hardhat run scripts/deploy/dVault/Strategy.js --network mainnet

TARGET_STRATEGY="AuraWETHStrategy" DVAULT_ADDRESS="0xebac2E85E95c67ac0baDC4dEFb58708De8F5C39b" npx hardhat run scripts/deploy/dVault/Strategy.js --network mainnet

TARGET_STRATEGY="CVXStrategy" DVAULT_ADDRESS="0xebac2E85E95c67ac0baDC4dEFb58708De8F5C39b" npx hardhat run scripts/deploy/dVault/Strategy.js --network mainnet

TARGET_STRATEGY="FXSStrategy" DVAULT_ADDRESS="0xebac2E85E95c67ac0baDC4dEFb58708De8F5C39b" npx hardhat run scripts/deploy/dVault/Strategy.js --network mainnet

TARGET_STRATEGY="YCRVStrategy" DVAULT_ADDRESS="0xebac2E85E95c67ac0baDC4dEFb58708De8F5C39b" npx hardhat run scripts/deploy/dVault/Strategy.js --network mainnet
```