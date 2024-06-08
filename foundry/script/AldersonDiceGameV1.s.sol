// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "../src/AldersonDiceGameV1.sol";
import {YearnVaultV3} from "../src/YearnVaultV3.sol";

contract AldersonDiceGameV1Script is Script {
    function run() external {

        // uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // vm.startBroadcast(deployerPrivateKey);

        // TODO: derive from the deployer private key
        address owner = address(this);
        vm.startBroadcast(owner);

        // TODO: read from env
        address devFund = owner;
        address prizeFund = owner;

        YearnVaultV3 prizeVault = YearnVaultV3(0x6FAF8b7fFeE3306EfcFc2BA9Fec912b4d49834C1);

        ERC20 prizeToken = ERC20(prizeVault.asset());

        uint256 mintFee = 10 ** prizeToken.decimals() / 2;
        uint256 price = 10 ** prizeToken.decimals();

        AldersonDiceNFT nft = new AldersonDiceNFT(owner);

        // TODO: mintFee that can be changed instead of the math like we have now
        AldersonDiceGameV1 game =
            new AldersonDiceGameV1(owner, devFund, prizeFund, nft, prizeVault, price, "ipfs://alderson-dice.eth/dice/");

        nft.upgrade(address(game));

        vm.stopBroadcast();
    }
}
