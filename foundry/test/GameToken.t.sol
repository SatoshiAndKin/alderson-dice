// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {GameToken, ERC20, ERC4626, PointsToken} from "../src/public_goods/GameToken.sol";
import {GameTokenMachine} from "../src/public_goods/GameTokenMachine.sol";
import {Test, console} from "@forge-std/Test.sol";
import {TestERC20} from "./TwabController.t.sol";
import {TwabController} from "@pooltogether-v5-twab-controller/TwabController.sol";
import {YearnVaultV3, YearnVaultV3Strategy} from "../src/external/YearnVaultV3.sol";

// TODO: make sure one user depositing doesn't reduce the value of another user's tokens
// TODO: check against the various inflation attacks
contract GameTokenTest is Test {
    TwabController twabController;
    GameTokenMachine gameTokenMachine;
    GameToken gameToken;
    PointsToken pointsToken;

    address alice;
    address earnings;
    address owner;

    YearnVaultV3 vault;
    ERC20 vaultAsset;
    uint256 vaultAssetShift;

    uint256 arbitrumFork;
    uint32 periodLength;

    function setUp() public {
        arbitrumFork = vm.createFork(vm.envString("ARBITRUM_RPC_URL"));

        vm.selectFork(arbitrumFork);
        vm.rollFork(212_419_055);

        alice = makeAddr("alice");
        earnings = makeAddr("earnings");
        owner = address(this);

        vault = YearnVaultV3(0x6FAF8b7fFeE3306EfcFc2BA9Fec912b4d49834C1);

        vaultAsset = ERC20(vault.asset());

        console.log("vaultAsset:", address(vaultAsset));

        periodLength = 1 weeks;

        // set the start offset to right now
        uint32 start = uint32(block.timestamp);
        // uint32 start = block.timestamp - 1 days;

        // TODO: i don't think we should need this, but timestamps seem weird with forked mode
        // TODO: really not sure about this +1
        vm.warp(start + 1);

        twabController = new TwabController(periodLength, start);

        gameTokenMachine = new GameTokenMachine(twabController);

        gameToken = gameTokenMachine.createGameToken(vault, earnings);

        pointsToken = gameToken.pointsToken();

        vaultAssetShift = 10 ** vaultAsset.decimals();

        require(vaultAssetShift > 0, "bad vault asset shift");

        deal(address(vaultAsset), alice, 1_000 * vaultAssetShift);
    }

    function test_simpleDepositAndWithdraw() public {
        require(gameToken.balanceOf(address(this)) == 0, "bad starting balance");
        require(gameToken.totalSupply() == 0, "bad total supply");

        vm.startPrank(alice);

        vaultAsset.approve(address(gameToken), type(uint256).max);

        uint256 start = block.timestamp;

        (uint256 numShares, uint256 numTokens) = gameToken.depositAsset(100 * vaultAssetShift);
        console.log("numShares:", numShares);
        console.log("numTokens:", numTokens);

        assertEq(vault.balanceOf(address(gameToken)), numShares, "bad vault balance for gameToken post depositAsset");

        assertEq(gameToken.balanceOf(alice), numTokens, "bad balance post mint");
        assertEq(vault.balanceOf(address(gameToken)), numShares, "bad vault balance for gameToken post mint");
        assertEq(vault.balanceOf(address(pointsToken)), 0, "bad vault balance for pointsToken post mint");

        // fake some interest before the twab period is finished
        require(! twabController.hasFinalized(block.timestamp), "now should not be finalized");

        uint256 fakedInterest = 100 * vaultAssetShift;
        deal(address(vault), address(gameToken), fakedInterest + numTokens);

        // TODO: what should these balances actually be?
        assertEq(vault.balanceOf(address(gameToken)), fakedInterest + numTokens, "bad vault balance for gameToken post deal");
        assertEq(vault.balanceOf(address(pointsToken)), 0, "bad vault balance for pointsToken post deal");
        assertEq(vault.balanceOf(alice), 0, "bad vault balance for alice post deal");

        // TODO: this isn't forwarding everything i expect it to. assert more and figure out why. something about excess calculating low
        (uint256 p, uint256 earnedShares) = gameToken.forwardEarnings();
        assertEq(p, 0, "bad period");
        require(earnedShares > 0, "bad earnedShares");
        assertEq(earnedShares, gameToken.totalForwardedShares(), "bad total forwarded shares");

        assertEq(pointsToken.balanceOf(address(gameToken)), earnedShares, "bad points balance for gameToken");
        assertEq(pointsToken.balanceOf(address(pointsToken)), 0, "bad points balance for pointsToken");
        assertEq(pointsToken.balanceOf(alice), 0, "bad points balance for alice");

        uint256 period0Shares = gameToken.pointsByPeriod(p);

        assertEq(period0Shares, earnedShares, "bad period 0 shares recorded");

        skip(uint256(periodLength));

        // TODO: this reverts inside of twab. why? it might be fixed now. try it out
        // require(twabController.balanceOf(address(gameToken), alice) == numTokens, "bad twab balance post mint");

        require(gameToken.totalSupply() == numTokens, "bad total supply post mint");

        uint256 sharesBurned = gameToken.withdrawAsset(numTokens);

        uint256 end = block.timestamp;

        console.log("shares burned:", sharesBurned);

        require(gameToken.balanceOf(alice) == 0, "bad balance post burn");
        require(gameToken.totalSupply() == 0, "bad total supply post burn");

        // finish this period and the next
        skip(uint256(periodLength * 3));
        require(twabController.hasFinalized(end), "end not finalized");

        uint256 twabBalance = twabController.getTwabBetween(address(gameToken), alice, start, end);
        uint256 twabSupply = twabController.getTotalSupplyTwabBetween(address(gameToken), start, end);

        console.log("twabBalance:", twabBalance);
        console.log("twabSupply:", twabSupply);

        // TODO: what balance should we actually expect
        require(twabBalance > 0, "too small of a twab balance post burn");
        require(twabBalance < numTokens, "too large of a twab balance post burn");
        require(twabBalance == twabSupply, "bad twab supply post burn");

        uint256 claimedPoints = gameToken.claimPoints(10, alice);
        console.log("claimed points:", claimedPoints);
        require(claimedPoints > 0, "no claimed points");

        // TODO: how many points should we have? i think it should be `fakedInterest`
        // require(gameToken.pointsOf(alice) == fakedInterest, "bad points post burn");

        uint256 claimedAssets = pointsToken.redeemPointsForAsset(alice, claimedPoints);
        console.log("claimed assets:", claimedAssets);
        console.log("fakedInterest:", fakedInterest);

        // this is reverting. something is wrong with our contracts because we should own 100% of the interest
        require(claimedAssets >= fakedInterest, "did not claim enough assets");
    }
}
