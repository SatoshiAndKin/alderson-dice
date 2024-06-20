// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@forge-std/Script.sol";
import "../src/GameTokenMachine.sol";
import "../src/GameToken.sol";
import "../src/YearnVaultV3.sol";

contract DeployGameTokenMachine is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        bytes32 saltGameTokenMachine = vm.envBytes32("SALT_GAME_TOKEN_MACHINE");

        TwabController twabController = TwabController(vm.envAddress("TWAB_CONTROLLER_ADDRESS"));

        GameTokenMachine machine = new GameTokenMachine{salt: saltGameTokenMachine}(twabController);

        YearnVaultV3 prizeVault = YearnVaultV3(0x6FAF8b7fFeE3306EfcFc2BA9Fec912b4d49834C1);

        machine.createGameToken(prizeVault);

        vm.stopBroadcast();
    }
}
