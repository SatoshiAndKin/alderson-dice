// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "../src/games/GrimeDiceV0.sol";
import {YearnVaultV3} from "../src/external/YearnVaultV3.sol";

contract DeployV0Script is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        bytes32 saltNft = vm.envBytes32("SALT_NFT");
        bytes32 saltGame = vm.envBytes32("SALT_GAME");

        // TODO: derive from the deployer private key?
        address owner = vm.envAddress("DEPLOYER");

        // TODO: read from env
        address devFund = owner;
        address prizeFund = owner;

        YearnVaultV3 prizeVault = YearnVaultV3(0x6FAF8b7fFeE3306EfcFc2BA9Fec912b4d49834C1);

        ERC20 prizeToken = ERC20(prizeVault.asset());

        /// dice can be redeemed for ~1 token
        uint256 price = 10 ** prizeToken.decimals();

        // 0.50 tokens to the devFund
        uint256 mintDevFee = price / 2;
        // 0.50 tokens to the prizeFund
        uint256 mintPrizeFee = mintDevFee;

        revert("finish refactoring this");

        // IntransitiveDiceNFT nft = new IntransitiveDiceNFT{salt: saltNft}(owner);

        // console.log("nft:", address(nft));

        // AldersonDiceGameV0 game = new AldersonDiceGameV0{salt: saltGame}(
        //     owner,
        //     devFund,
        //     prizeFund,
        //     nft,
        //     prizeVault,
        //     price,
        //     mintDevFee,
        //     mintPrizeFee,
        //     "ipfs://alderson-dice.eth/dice/"
        // );

        // console.log("game:", address(game));

        // revert("upgrades are a wip");
        // // nft.upgrade(address(game), false);

        // vm.stopBroadcast();
    }
}
