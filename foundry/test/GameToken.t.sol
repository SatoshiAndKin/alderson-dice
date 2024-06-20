// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Test, console} from "@forge-std/Test.sol";
import {GameToken, GameTokenMachine, ERC20, ERC4626} from "../src/GameToken.sol";
import {YearnVaultV3, YearnVaultV3Strategy} from "../src/YearnVaultV3.sol";
import {TwabController} from "@pooltogether-v5-twab-controller/TwabController.sol";

// TODO: make sure one user depositing doesn't reduce the value of another user's tokens
// TODO: check against the various inflation attacks
contract GameTokenTest is Test {
    TwabController twabController;
    GameTokenMachine gameTokenMachine;
    GameToken gameToken;

    address alice;
    address earnings;
    address owner;

    YearnVaultV3 vault;
    ERC20 vaultAsset;
    uint256 vaultAssetShift;

    uint256 arbitrumFork;

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

        uint32 periodLength = 1 weeks;
        uint32 periodOffset = uint32(block.timestamp / periodLength);

        // TODO: one already exists for pooltogether, doesn't it? use that if the period length matches what we want
        TwabController twabController = new TwabController(periodLength, periodOffset);

        gameTokenMachine = new GameTokenMachine(twabController);

        gameToken = gameTokenMachine.createGameToken(vault, earnings);

        vaultAssetShift = 10 ** vaultAsset.decimals();

        deal(address(vaultAsset), alice, 1_000 * vaultAssetShift);
    }

    function testSimpleDepositAndWithdraw() public {
        require(gameToken.balanceOf(address(this)) == 0, "bad starting balance");
        require(gameToken.totalSupply() == 0, "bad total supply");

        vm.startPrank(alice);

        vaultAsset.approve(address(gameToken), type(uint256).max);

        // TODO: return the number of shares, too?
        uint256 numTokens = gameToken.depositAsset(100 * vaultAssetShift);

        console.log("numTokens:", numTokens);

        require(gameToken.balanceOf(alice) == numTokens, "bad balance post mint");

        require(gameToken.totalSupply() == numTokens, "bad total supply post mint");

        uint256 sharesBurned = gameToken.withdrawAsset(numTokens);

        console.log("shares burned:", sharesBurned);

        require(gameToken.balanceOf(alice) == 0, "bad balance post burn");
        require(gameToken.totalSupply() == 0, "bad total supply post burn");

        // TODO: what else should we test?
    }
}
