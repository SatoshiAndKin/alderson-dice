// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {ERC20} from "@solady/tokens/ERC20.sol";
import {Test, console} from "@forge-std/Test.sol";
import {PointsToken} from "../src/public_goods/PointsToken.sol";
import {GameToken, GrimeDiceV0, ERC4626, LibPRNG} from "../src/games/GrimeDiceV0.sol";
import {GameTokenMachine, TwabController} from "../src/public_goods/GameTokenMachine.sol";
import {YearnVaultV3, YearnVaultV3Strategy} from "../src/external/YearnVaultV3.sol";

contract GrimeDiceV0Test is Test {
    using LibPRNG for LibPRNG.PRNG;

    GameTokenMachine gameTokenMachine;
    GameToken gameToken;
    PointsToken pointsToken;
    GrimeDiceV0 diceToken;
    TwabController twabController;

    address owner;
    address devFund;
    address prizeFund;

    YearnVaultV3 prizeVault;
    ERC20 prizeToken;

    uint256 arbitrumFork;

    // this setup function feels really heavy. is this the right way to do things?
    function setUp() public {
        arbitrumFork = vm.createFork(vm.envString("ARBITRUM_RPC_URL"));

        vm.selectFork(arbitrumFork);
        vm.rollFork(212_419_055);

        owner = address(this);
        devFund = makeAddr("devFund");
        prizeFund = makeAddr("prizeFund");

        prizeVault = YearnVaultV3(0x6FAF8b7fFeE3306EfcFc2BA9Fec912b4d49834C1);

        prizeToken = ERC20(prizeVault.asset());

        // TODO: rethink prices now that game tokens are involved?
        uint256 price = 10 ** prizeToken.decimals();

        uint256 mintDevFee = price / 2;
        uint256 mintPrizeFee = price / 2;

        // give enough tokens to buy 100 dice
        deal(address(prizeToken), address(this), 1_000 * price);

        // TODO: what should offset be? i think we should round the nearest epoch week
        twabController = new TwabController(1 weeks, uint32(block.timestamp - 1));

        gameTokenMachine = new GameTokenMachine(twabController);

        // TODO: rename createGameToken to createGameChips
        gameToken = gameTokenMachine.createGameToken(prizeVault, owner);

        // changing price while we run breaks redeeming dice. but it makes tests a bit of a pain. i guess make a helper function for this?
        // how should we allow changing the tokenURI?
        diceToken = new GrimeDiceV0(
            devFund,
            prizeFund,
            gameToken,
            price,
            mintDevFee,
            mintPrizeFee,
            10,
            "ipfs://alderson-dice.eth/dice/"
        );
    }

    function test_buySomeDice() public {
        revert("rewrite this after the refactor"); // the vault tokens are now held by the game tokens. we need to check game token balance here instead

        // uint256 diceBalance = 0;

        // // TODO: this will have to change if we add more dice of the same color eventually i think we want 30 or even 150 dice
        // uint256 numColors = diceToken.NUM_COLORS();

        // // dice indexes start at 1! need `<=`
        // for (uint256 i = 0; i <= numColors; i++) {
        //     diceBalance += nft.balanceOf(owner, i);
        // }

        // require(diceBalance == 0, "unexpected balance");
        // require(game.prizeTokenAvailable() == 0, "unexpected prizeToken available. should be 0");

        // prizeToken.approve(address(game), type(uint256).max);

        // game.buyNumDice(owner, 10);

        // uint256[] memory returnIds = new uint256[](numColors);
        // uint256[] memory returnAmounts = new uint256[](numColors);
        // for (uint256 i = 0; i < numColors; i++) {
        //     // dice indexes start at 1! color indexes start at 0!
        //     uint256 j = i + 1;

        //     returnIds[i] = j;
        //     returnAmounts[i] = nft.balanceOf(owner, j);

        //     diceBalance += returnAmounts[i];
        // }

        // require(diceBalance == 10, "unexpected dice balance");

        // require(prizeToken.balanceOf(address(game)) == 0, "unexpected prizeToken balance");
        // require(prizeVault.balanceOf(address(game)) > 0, "unexpected vaultToken balance");

        // require(game.sponsorships(prizeFund) == 0, "unexpected prizeFund sponsorship");

        // // TODO: because of some rounding inside the yearn vault, this is always a little lower than we expected. but it should be close
        // // TODO: it is a little confusing though. look more into it. our first code just used the input amounts but that seems unsafe
        // require(game.sponsorships(devFund) > game.refundPrice() / 2 * 10 * 95 / 100, "unexpected devFund sponsorship");

        // uint256 prizeTokenAvailable = diceToken.prizeTokenAvailable();

        // console.log("prizeTokenAvailable after mint", prizeTokenAvailable);

        // // TODO: what should the amount be?
        // require(prizeTokenAvailable > 0, "no prizeToken available. should be some from the dice purchase");

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

        // require(game.prizeTokenAvailable() > prizeTokenAvailable, "unexpected prizeToken available");

        // TODO: take a range and have a helper function for this
        // uint256 burned = game.returnDice(address(this), returnIds, returnAmounts);

        // // TODO: what value should we expect?
        // require(burned > 0, "unexpected burned");

        // we've burned all the dice we minted. there should still be money in the dev fund
        // TODO: what value should we expect?
        // require(prizeVault.balanceOf(address(diceToken)) > 0, "unexpected game prizeVault balance");
        // require(diceToken.prizeTokenAvailable() > 0, "unexpected prizeToken available");
        // require(diceToken.sponsorships(devFund) > 0, "unexpected devFund sponsorship");
        // require(diceToken.totalSponsorships() > 0, "unexpected totalSponsorships");
    }

    function test_vaultDepositAndWithdraw() public {
        uint256 amount = 1_000 * 10 ** prizeToken.decimals();

        deal(address(prizeToken), address(this), amount);

        uint256 expectedShares = prizeVault.previewDeposit(amount);

        prizeToken.approve(address(prizeVault), amount);
        uint256 shares = prizeVault.deposit(amount, address(this));

        require(expectedShares == shares, "unexpected shares");

        uint256 expectedRedeem = prizeVault.previewRedeem(shares);

        // -1 because 1 wei loss is common
        require(expectedRedeem >= amount - 1);
    }

    // function test_twoDiceSkirmish() public {
    //     uint16 color0 = 0;
    //     uint16 color1 = 4;

    //     console.log("color0", color0);
    //     console.log("color1", color1);

    //     LibPRNG.PRNG memory prng;

    //     (string memory name0, string memory symbol0) = game.dice(color0);
    //     (string memory name1, string memory symbol1) = game.dice(color1);

    //     console.log("name0", name0);
    //     console.log("name1", name1);

    //     console.log("symbol0", symbol0);
    //     console.log("symbol1", symbol1);

    //     assertEq(name0, "Red", "not red");
    //     assertEq(name1, "Olive", "not olive");

    //     // color1 (olive) is stronger than color0 (red)
    //     // skirmish out of 10 should be good odds. u8 max should be unlikely to fail
    //     // TODO: what are the odds that they lose?
    //     // TODO: better to do do a bunch of games of 10 rounds?
    //     (uint256 wins0, uint256 wins1, uint256 ties) = game.skirmishColors(prng, color0, color1);

    //     console.log("wins0", wins0);
    //     console.log("wins1", wins1);
    //     console.log("ties", ties);

    //     require(wins1 > wins0, "unexpected wins");
    //     require(ties < wins1, "unexpected ties");
    // }

    function test_rollDice() public view {
        // remember, dieIds start at 1, but colors start at 0!
        uint256 die0 = 5;
        uint256 die1 = 4;

        console.log("die0", die0);
        console.log("die1", die1);

        uint256 color0 = diceToken.getColor(die0);
        uint256 color1 = diceToken.getColor(die1);

        console.log("color0", color0);
        console.log("color1", color1);

        // TODO: why aren't pips here?
        (string memory name0, string memory symbol0) = diceToken.dice(color0);
        (string memory name1, string memory symbol1) = diceToken.dice(color1);

        console.log("name0", name0);
        console.log("name1", name1);

        console.log("symbol0 (from color)", symbol0);
        console.log("symbol1 (from color)", symbol1);

        // TODO: i just randomly set die# until these passed.
        require(color0 == 0, "unexpected color0");
        require(color1 == 4, "unexpected color1");

        uint256 bagSize = diceToken.NUM_DICE_BAG();

        uint256[] memory bag0 = new uint256[](bagSize);
        uint256[] memory bag1 = new uint256[](bagSize);
        for (uint256 i = 0; i < bagSize; i++) {
            bag0[i] = die0;
            bag1[i] = die1;
        }

        // TODO: make sure this matches what we got earlier
        console.log("symbol0 (from die)", diceToken.symbol(die0));
        console.log("symbol1 (from die)", diceToken.symbol(die1));

        LibPRNG.PRNG memory prng;

        // color1 (olive) is stronger than color0 (red)
        // skirmish out of 10 should be good odds. u8 max should be unlikely to fail
        // TODO: what are the odds that they lose?
        // TODO: better to do do a bunch of games of 10 rounds?
        uint256[] memory pips0 = diceToken.rollDice(prng, bag0);
        uint256[] memory pips1 = diceToken.rollDice(prng, bag1);

        (uint256 wins0, uint256 wins1, uint256 ties) = diceToken.scorePips(pips0, pips1);

        console.log("wins0", wins0);
        console.log("wins1", wins1);
        console.log("ties", ties);

        require(wins1 > wins0, "unexpected wins");
        require(ties < wins1, "unexpected ties");
        require(wins0 + wins1 + ties == 10, "unexpected rounds");
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

    // TODO: think about this test now that the mint contract isn't split apart
    // function testFuzz_prankedNftMint(address to, uint256 id) public {
    //     vm.assume(to != address(0));

    //     uint256 amount = 10;

    //     vm.assume(id > 0);
    //     vm.assume(id < 6);

    //     uint256[] memory mintIds = new uint256[](1);
    //     uint256[] memory mintAmounts = new uint256[](1);

    //     mintIds[0] = id;
    //     mintAmounts[0] = amount;

    //     vm.prank(address(gameToken));
    //     gameToken.mint(to, mintIds, mintAmounts);

    //     // require(nft.balanceOf(to, 0) == 0, "zero balance isn't empty");
    //     // require(nft.balanceOf(to, id) == amount, "unexpected balance");
    //     // require(nft.balanceOf(to, id + 1) == 0, "other balance isn't empty");

    //     revert("finish refactoring this");
    // }
}
