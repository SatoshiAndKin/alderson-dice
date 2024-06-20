// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@forge-std/Script.sol";
import "../src/GameToken.sol";

contract DeployGameTokenMachine is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        bytes32 saltGameTokenMachine = vm.envBytes32("SALT_GAME_TOKEN_MACHINE");

        uint32 periodLength = 1 weeks;
        // TODO: what should this be?
        uint32 periodOffset = 0;

        // TODO: can we just re-use the existing twab controller? maybe if ones set in the env, use it. otherwise, deploy.
        TwabController twabController = new TwabController(periodLength, periodOffset);

        new GameTokenMachine{salt: saltGameTokenMachine}(twabController);

        vm.stopBroadcast();
    }
}
