# angry-safe-contracts

## how to deploy

### create .env
PRIVATE_KEY=...

BSC_RPC_URL=https://bsc-dataseed.binance.org/

### in terminal do
source .env

forge script script/AngrySafe.s.sol:DeployScript --rpc-url $BSC_RPC_URL --broadcast --verify -vvvv
