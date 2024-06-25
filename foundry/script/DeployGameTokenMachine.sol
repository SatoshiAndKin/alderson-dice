// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import "@forge-std/Script.sol";
import "../src/public_goods/GameTokenMachine.sol";
import "../src/public_goods/GameToken.sol";
import "../src/external/YearnVaultV3.sol";

contract DeployGameTokenMachine is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        bytes32 saltGameTokenMachine = vm.envBytes32("SALT_GAME_TOKEN_MACHINE");

        TwabController twabController = TwabController(vm.envAddress("TWAB_CONTROLLER_ADDRESS"));

        GameTokenMachine machine = new GameTokenMachine{salt: saltGameTokenMachine}(twabController);

        YearnVaultV3 vault = YearnVaultV3(0x6FAF8b7fFeE3306EfcFc2BA9Fec912b4d49834C1);

        // TODO: where should we actually send the earnings? we need a splitter contract that lets players burn their points for rewards
        machine.createGameToken(vault, msg.sender);

        // assert that the game asset is USDC?

        vm.stopBroadcast();
    }
}
