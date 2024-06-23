// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {ERC20} from "@solady/tokens/ERC20.sol";
import {Test, console} from "@forge-std/Test.sol";
import {GameToken, GrimeDiceV0, ERC4626, LibPRNG} from "../src/GrimeDiceV0.sol";
import {GameTokenMachine, TwabController} from "../src/GameTokenMachine.sol";
import {YearnVaultV3, YearnVaultV3Strategy} from "../src/external/YearnVaultV3.sol";

// TODO: how should we 
contract GrimeDiceV0Test is Test {
    function test_fakedReport() public {
        // fake a bunch of yield on the vault
        // deal(address(prizeToken), address(prizeVault), 1_000_000 * 10 ** prizeToken.decimals());

        // YearnVaultV3Strategy strategy0 = prizeVault.default_queue(0);

        // address keeper = strategy0.keeper();

        // vm.prank(keeper);
        // strategy0.report();

        // TODO: theres still more to call to get the vault to realize the donated tokens. i probably need to wait some time, too
        // TODO: how do we get the reporting manager?
        // address reporting_manager = prizeVault.roles(uint256(YearnVaultV3.Role.REPORTING_MANAGER));

        // vm.prank(reporting_manager);
        // prizeVault.process_report(strategy0);

        // prizeTokenAvailable = game.prizeTokenAvailable();
        // console.log("prizeTokenAvailable after report", prizeTokenAvailable);
        revert("rewrite this");
    }
}