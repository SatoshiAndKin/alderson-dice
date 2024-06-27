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
        // TODO: really not sure about this
        vm.warp(start + 1 days);

        twabController = new TwabController(periodLength, start);

        gameTokenMachine = new GameTokenMachine(twabController);

        gameToken = gameTokenMachine.createGameToken(vault, earnings);

        pointsToken = gameToken.pointsToken();

        vaultAssetShift = 10 ** vaultAsset.decimals();

        deal(address(vaultAsset), alice, 1_000 * vaultAssetShift);
    }

    function test_simpleDepositAndWithdraw() public {
        require(gameToken.balanceOf(address(this)) == 0, "bad starting balance");
        require(gameToken.totalSupply() == 0, "bad total supply");

        vm.startPrank(alice);

        vaultAsset.approve(address(gameToken), type(uint256).max);

        uint256 start = block.timestamp;

        // TODO: return the number of shares, too?
        uint256 numTokens = gameToken.depositAsset(100 * vaultAssetShift);
        console.log("numTokens:", numTokens);
        require(gameToken.balanceOf(alice) == numTokens, "bad balance post mint");

        // fake some interest before the twab period is finished
        require(! twabController.hasFinalized(block.timestamp), "now should not be finalized");
        uint256 fakedInterest = 100 * vaultAssetShift;
        deal(address(vault), address(gameToken), fakedInterest);
        
        // TODO: better asserts
        (uint256 p, uint256 x, uint256 y) = gameToken.forwardEarnings();
        require(p == 0, "bad p");
        require(x > 0, "no x");
        require(x == gameToken.totalForwardedShares(), "bad total forwarded shares");
        require(y > 0, "no y");
        require(y == gameToken.totalForwardedValue(), "bad total forwarded value");

        (uint256 period0Shares, uint256 period0Value) = gameToken.forwardedEarningsByPeriod(0);

        require(period0Shares > 0, "no period 0 shares recorded");
        require(period0Value > 0, "no period 0 value recorded");

        skip(uint256(periodLength));

        // TODO: this reverts inside of twab. why? it might be fixed now. try it out
        // require(twabController.balanceOf(address(gameToken), alice) == numTokens, "bad twab balance post mint");

        require(gameToken.totalSupply() == numTokens, "bad total supply post mint");

        uint256 sharesBurned = gameToken.withdrawAsset(numTokens);

        uint256 end = block.timestamp;

        console.log("shares burned:", sharesBurned);

        require(gameToken.balanceOf(alice) == 0, "bad balance post burn");
        require(gameToken.totalSupply() == 0, "bad total supply post burn");

        // finish this period
        skip(uint256(periodLength));
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

        // TODO: how much of the fakedInterest should be ours? we don't have the period lined up to take 100%
        // TODO: this is not exactly what we want. claimed assets should be converted to shares and then compared for equality
        require(claimedAssets > claimedPoints, "bad points value");
    }
}
