// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {ERC20} from "@solady/tokens/ERC20.sol";
import {Test, console} from "@forge-std/Test.sol";
import {TwabController} from "@pooltogether-v5-twab-controller/TwabController.sol";

contract TestERC20 is ERC20 {
    function name() public pure override returns (string memory) {
        return "Test";
    }
    function symbol() public pure override returns (string memory) {
        return "T";
    }
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}

contract TwabControllerTest is Test {

    uint256 arbitrumFork;
    uint32 periodLength;
    uint32 periodOffset;
    TestERC20 token;
    TwabController twabController;

    function setUp() public {
        arbitrumFork = vm.createFork(vm.envString("ARBITRUM_RPC_URL"));

        vm.selectFork(arbitrumFork);
        vm.rollFork(212_419_055);

        periodLength = 1 weeks;
        
        // TODO: i don't think we should need this, but timestamps seem weird with forked mode
        uint32 when = uint32(block.timestamp / periodLength * periodLength);
        uint256 now_ = block.timestamp + 1;

        twabController = new TwabController(periodLength, when);

        vm.warp(now_);

        token = new TestERC20();
    }

    // TODO: do this as a fuzz test
    function testFuzz_simpleMintAndBurn(uint96 amount) public {
        vm.assume(amount > 0);

        address alice = makeAddr("alice");

        // initial state
        uint256 x = twabController.totalSupply(address(this));

        assertEq(x, 0, "bad total supply");

        // minting
        vm.startPrank(address(token));

        twabController.mint(alice, amount);

        x = twabController.totalSupply(address(token));

        assertEq(x, amount, "bad total supply after mint");

        // burning
        twabController.burn(alice, amount);

        x = twabController.totalSupply(address(this));

        assertEq(x, 0, "bad total supply after burn");
    }
}
