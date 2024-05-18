// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {AldersonDiceNFT, AldersonDiceGameV1, ERC20, ERC4626} from "../src/AldersonDiceGameV1.sol";

contract AldersonDiceGameV1Test is Test {
    AldersonDiceNFT public nft;
    AldersonDiceGameV1 public game;

    address owner;
    address devFund;

    ERC4626 prizeVault;
    ERC20 prizeToken;

    uint256 arbitrumFork;

    function setUp() public {
        arbitrumFork = vm.createFork(vm.envString("ARBITRUM_RPC_URL"));

        vm.selectFork(arbitrumFork);
        vm.rollFork(212_419_055);

        owner = address(this);
        devFund = makeAddr("devFund");

        prizeVault = ERC4626(0x6FAF8b7fFeE3306EfcFc2BA9Fec912b4d49834C1);

        prizeToken = ERC20(prizeVault.asset());

        nft = new AldersonDiceNFT(owner, 1 days);

        game = new AldersonDiceGameV1(owner, devFund, nft, prizeVault, 0);

        nft.upgrade(address(game));
    }

    function test_twoDiceSkirmish() public view {
        uint16 color0 = game.color(0);
        uint16 color1 = game.color(1);
        
        console.log("color0", color0);
        console.log("color1", color1);

        require(color0 == 1);
        require(color1 == 4);

        bytes32 seed = bytes32(0);

        // color1 (olive) is stronger than color0 (red)
        // TODO: what are the odds that they lose?
        (uint8 wins0, uint8 wins1, uint8 ties) = game.skirmish(seed, 0, 1, 10);

        console.log("wins0", wins0);
        console.log("wins1", wins1);
        console.log("ties", ties);

        require(wins1 > wins0);
        require(ties < wins1);
    }

    function testRelease() public {
        require(game.owner() == owner);
        require(game.devFund() == devFund);

        // TODO: allow setting the price one last time?
        game.release();

        require(game.owner() == address(0));
        require(game.devFund() == devFund);
    }

    function testFuzz_mint(address to, uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < 100);

        vm.prank(address(game));
        nft.mint(to, amount);

        require (nft.nextTokenId() == amount);

        // TODO: loop to check all the balances!
        require (nft.balanceOf(to, 0) == 1);
        require (nft.balanceOf(to, amount - 1) == 1);
        require (nft.balanceOf(to, amount) == 0);
    }
}
