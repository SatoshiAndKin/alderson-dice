# Alderson Dice

An on-chain non-transitive dice game inspired by pooltogether.

## The Smart Contracts

- GameToken.sol
- GameTokenMachine.sol
- GrimDiceV0.sol
- PointsToken.sol
- PrizeFund.sol

All contracts are designed as immutable from the start. No ownership or privileged addresses will exist in this code\*.

- Of course, the vault could do plenty of high risk custodial things on upgradable contracts or have an exploit and get rekt, but this repo's code shouldn't be to blame for that.

## Development

Start anvil:

    anvil --fork-block-number 212419055 --fork-url https://rpc.ankr.com/arbitrum

Deploy to anvil:

    forge script script/DeployGameTokenMachine.sol --fork-url http://localhost:8545 --broadcast

    forge script script/DeployV0.sol --fork-url http://localhost:8545 --broadcast

    cast rpc evm_setIntervalMining 4
