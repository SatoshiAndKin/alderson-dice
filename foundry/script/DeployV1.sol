// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "../src/AldersonDiceGameV1.sol";
import {YearnVaultV3} from "../src/YearnVaultV3.sol";

contract DeployV1Script is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // TODO: derive from the deployer private key?
        address owner = vm.envAddress("DEPLOYER");

        // TODO: read from env
        address devFund = owner;
        address prizeFund = owner;

        YearnVaultV3 prizeVault = YearnVaultV3(0x6FAF8b7fFeE3306EfcFc2BA9Fec912b4d49834C1);

        ERC20 prizeToken = ERC20(prizeVault.asset());

        /// @notice the base dice value
        /// @notice due to rounding errors depositing and withdrawing from vaults, this might not be the exact value
        uint256 price = 10 ** prizeToken.decimals();

        // 50 cents to the devFund
        uint256 mintDevFee = price / 2;
        // 50 cents to the prizeFund
        uint256 mintPrizeFee = mintDevFee;

        // TODO: CREATE2!
        AldersonDiceNFT nft = new AldersonDiceNFT(owner);

        console.log("nft:", address(nft));

        // TODO: CREATE2!
        AldersonDiceGameV1 game =
            new AldersonDiceGameV1(owner, devFund, prizeFund, nft, prizeVault, price, mintDevFee, mintPrizeFee, "ipfs://alderson-dice.eth/dice/");

        console.log("game:", address(game));

        nft.upgrade(address(game), false);

        vm.stopBroadcast();
    }
}
