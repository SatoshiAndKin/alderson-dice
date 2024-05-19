// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {AldersonDiceNFT, AldersonDiceGameV1, ERC20, ERC4626, LibPRNG} from "../src/AldersonDiceGameV1.sol";

contract AldersonDiceGameV1Test is Test {
    using LibPRNG for LibPRNG.PRNG;

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

        nft = new AldersonDiceNFT(owner);

        game = new AldersonDiceGameV1(owner, devFund, nft, prizeVault, 0, 1 weeks, "ipfs://alderson-dice.eth/dice/");

        // TODO: how should we multiple by decimals here? math.pow?
        // game.setPrice(1);     

        nft.upgrade(address(game));
    }

    function test_buySomeDice() public {
        uint256 sum = 0;

        uint256 numColors = game.NUM_COLORS();

        // dice indexes start at 1! need `<=`
        for (uint256 i = 0; i <= numColors; i++) {
            sum += nft.balanceOf(owner, i);
        }

        require(sum == 0, "unexpected balance");

        game.buyNumDice(owner, 10);

        // dice indexes start at 1! need `<=`
        for (uint256 i = 0; i <= numColors; i++) {
            sum += nft.balanceOf(owner, i);
        }

        // TODO: is there a helper for comparisons like this?
        require(sum == 10, "unexpected balance");
    }

    function test_twoDiceSkirmish() public view {
        uint16 color0 = 1;
        uint16 color1 = 4;

        console.log("color0", color0);
        console.log("color1", color1);

        require(color0 == 1);
        require(color1 == 4);

        LibPRNG.PRNG memory prng;

        // color1 (olive) is stronger than color0 (red)
        // skirmish out of 10 should be good odds. u8 max should be unlikely to fail
        // TODO: what are the odds that they lose?
        // TODO: better to do do a bunch of games of 10 rounds?
        (uint8 wins0, uint8 wins1, uint8 ties) = game.skirmish(prng, color0, color1, type(uint8).max);

        console.log("wins0", wins0);
        console.log("wins1", wins1);
        console.log("ties", ties);

        require(wins1 > wins0);
        require(ties < wins1);
    }

    // // TODO: v1 doesn't need the release function. there will definitely be an upgrade before it is ready
    // function testRelease() public {
    //     require(game.owner() == owner);
    //     require(game.devFund() == devFund);

    //     // TODO: allow setting the price one last time?
    //     game.release();

    //     require(game.owner() == address(0));
    //     require(game.devFund() == devFund);
    // }

    function testFuzz_prankedNftMint(address to, uint256 id) public {
        vm.assume(to != address(0));

        uint256 amount = 10;

        vm.assume(id > 0);
        vm.assume(id < 6);

        uint256[] memory mintIds = new uint256[](1);
        uint256[] memory mintAmounts = new uint256[](1);

        mintIds[0] = id;
        mintAmounts[0] = amount;

        vm.prank(address(game));
        nft.mint(to, mintIds, mintAmounts);

        require(nft.balanceOf(to, 0) == 0, "zero balance isn't empty");
        require(nft.balanceOf(to, id) == amount, "unexpected balance");
        require(nft.balanceOf(to, id + 1) == 0, "other balance isn't empty");
    }
}
