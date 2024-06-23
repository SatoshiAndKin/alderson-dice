# Alderson Dice

An on-chain non-transitive dice game inspired by pooltogether.

The best thing crypto has found a product-market fit on is gambling. But gambling can be really problematic. People want to do it regardless though. So how do we make it safer and fun? How do we use it as a tool to teach people about how crypto works and how to secure it and how to script it and code against it? I hope this game can answer those questions.

## User Guide

The primary way I expect this game to be used during development:

1. Deposit USDC into the "Gameified yvUSDC" contract on Arbitrum.

- You will receive a "gamified" token that can be used for multiple games.
- So long as the ERC 4626 vault operates successfully, these "gameified" tokens can always be exchanged 1:1 for the original deposit.

2. Instead of receiving the vault's interest yourself, you receive points.

- Any interest earned by the underlying vault is held by the GameToken contracts.
- Points can be exchanged for the interest earned, or they can be used to play games.

3. These "gamified" tokens can then be deposited into any of the games you want to play.

- The points earned by the depoisted token will now be sent to the game. The game will track your contribution of these points.
- Most games will take a fee on deposit. This fee goes to fund the current prize pool and to pay the developers.

Game 1: DevFund - This is just a test contract. Getting a game working on chain where nothing can be rugged is a real challenge so this serves as a placeholder. - This game redirects 100% of the interest to a developer fund. - Any funds sent to the developer will be used to buy nachos and whatever else the developer needs. - PointsTokens will be given out based on interest sent to the developer. - There is no concrete plan for these PointsTokens.

Game 2: Alderson Dice V0 - Interest is split: 1/2 developer, 1/2 points exchange - Any funds sent to the developer will be used to buy nachos or whatever else the developer needs. - PointsTokens will be given out based on interest sent to the developer. - PointsTokens can be exchanged for an equivalent amount of interest. - To simplify development, the dice rolling is handled off-chain and there is no wagering.

Game 3: Alderson Dice V1 - Interest is split: 1/10 developer, 9/10 points exchange - PointsTokens will be given out based on interest sent to the PrizeFund. - PointsTokens will be given out based on on-chain wins and losses.

## The Smart Contracts

- GameToken.sol
- GameTokenMachine.sol
- GrimDiceV0.sol
- PointsToken.sol
- PrizeFund.sol

All contracts are designed as immutable from the start. No ownership or privileged addresses will exist in this code\*.

- `*` Of course, the vault could do plenty of high risk custodial things on upgradable contracts or have an exploit and get rekt, but this repo's code shouldn't be to blame for that.

## Development

Start anvil:

    anvil --fork-block-number 212419055 --fork-url https://rpc.ankr.com/arbitrum

Deploy to anvil:

    forge script script/DeployGameTokenMachine.sol --fork-url http://localhost:8545 --broadcast

    forge script script/DeployV0.sol --fork-url http://localhost:8545 --broadcast

    cast rpc evm_setIntervalMining 4
