// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {ERC20} from "@solady/tokens/ERC20.sol";
import {Test, console} from "@forge-std/Test.sol";
import {YearnVaultV3, YearnVaultV3Strategy} from "../src/external/YearnVaultV3.sol";

contract YearnVaultV3Test is Test {
    YearnVaultV3 yvUsdc;
    ERC20 asset;

    uint256 arbitrumFork;

    function setup() public {
        arbitrumFork = vm.createFork(vm.envString("ARBITRUM_RPC_URL"));

        vm.selectFork(arbitrumFork);
        vm.rollFork(212_419_055);

        yvUsdc = YearnVaultV3(0x6FAF8b7fFeE3306EfcFc2BA9Fec912b4d49834C1);

        asset = ERC20(yvUsdc.asset());
    }

    function test_fakedReport() public {
        YearnVaultV3Strategy strategy0 = yvUsdc.default_queue(0);

        // fake a bunch of yield on the strategy
        deal(address(strategy0), address(yvUsdc), 1_000_000 * 10 ** asset.decimals());

        address keeper = strategy0.keeper();

        // TODO: prank as the strategy instead?
        vm.prank(keeper);
        strategy0.report();

        // TODO: theres still more to call to get the vault to realize the donated tokens. i probably need to wait some time, too
        // TODO: how do we get the reporting manager?
        // address reporting_manager = yvUsdc.roles(uint256(YearnVaultV3.Role.REPORTING_MANAGER));

        // TODO: prank as the reporting_manager instead? pranking as the contract is probably wrong
        vm.prank(address(yvUsdc));
        yvUsdc.process_report(strategy0);

        // prizeTokenAvailable = game.prizeTokenAvailable();
        // console.log("prizeTokenAvailable after report", prizeTokenAvailable);

        revert("finish this");
    }
}