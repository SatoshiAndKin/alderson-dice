// SPDX-License-Identifier: GPL-3.0
// TODO: i don't love the name. kind of like chips in a casino or nickles in an arcade
pragma solidity 0.8.26;

// TODO: move most of the NFT logic here
// TODO: give tokens based on deposits. make sure someone depositing can't reduce someone else's withdraw
// TODO: factory contract to deploy our tokens for any vault tokens

import {console} from "@forge-std/console.sol";
import {ERC20} from "@solady/tokens/ERC20.sol";
import {ERC4626} from "@solady/tokens/ERC4626.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {TwabController} from "@pooltogether-v5-twab-controller/TwabController.sol";

contract PointsToken is ERC20 {
    using SafeTransferLib for address;

    address public immutable gameToken;
    ERC4626 public immutable vault;

    // TODO: this tracks the balances, but ERC20 also tracks the balance. we should probably improve that
    TwabController public immutable twabController;

    /// @notice vault and twabController **must** match GameToken(msg.sender)!
    constructor(ERC4626 _vault, TwabController _twabController) {
        gameToken = msg.sender;
        twabController = _twabController;
        vault = _vault;

        // TODO: do we want the game token to be able to pull points back?
        // vault.approve(msg.sender, type(uint256).max);
    }

    /// @dev Hook that is called after any transfer of tokens.
    /// This includes minting and burning.
    /// TODO: Time-weighted average balance controller from pooltogether takes a uint96, not a uint256. this might cause problems
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        uint96 amount96 = SafeCastLib.toUint96(amount);

        if (from == address(0)) {
            twabController.mint(to, amount96);
        } else if (to == address(0)) {
            twabController.burn(from, amount96);
        } else {
            twabController.transfer(from, to, amount96);
        }
    }

    /// @dev we don't control the vault and so name might change
    function name() public view override returns (string memory) {
        // we could cache these, but these methods are mostly used off-chain and so this is fine
        return string(abi.encodePacked("Points from ", vault.name()));
    }

    /// @dev we don't control the vault and so symbol might change
    function symbol() public view override returns (string memory) {
        // we could cache this locally, but these methods are mostly used off-chain and so this is fine
        return string(abi.encodePacked("p", vault.symbol()));
    }

    // TODO: limit minting points to the GameToken?
    /// @notice make sure to approve the transfer of points before calling this function!
    function mint(address to, uint256 numPoints) public {
        // TODO: approvals needed
        uint256 balance = vault.balanceOf(msg.sender);

        console.log("minting points for", to, numPoints, balance);

        // TODO: this is reverting with insufficient funds. why?
        address(vault).safeTransferFrom(msg.sender, address(this), numPoints);

        _mint(to, numPoints);
    }

    function redeemPointsForVault(address player, uint256 numPoints) public {
        if (msg.sender != player) {
            _spendAllowance(msg.sender, player, numPoints);
        }

        _burn(player, numPoints);

        address(vault).safeTransfer(player, numPoints);
    }

    function redeemPointsForAsset(address player, uint256 numPoints) public returns (uint256 assets) {
        if (msg.sender != player) {
            _spendAllowance(msg.sender, player, numPoints);
        }

        _burn(player, numPoints);

        // withdraw takes the amount of asset and returns the amount of shares
        // redeem takes the number of shares and returns the amount of ass
        assets = vault.redeem(numPoints, player, address(this));
    }

    function excess() public view returns (uint256) {
        // TODO: i think this needs a refactor. i think we want prizes to all be tracked in shares and not in asset!
        uint256 valueNeeded = totalSupply();

        uint256 sharesNeeded = vault.previewWithdraw(valueNeeded);

        uint256 shareBalance = vault.balanceOf(address(this));

        if (sharesNeeded > shareBalance) {
            return 0;
        }

        return shareBalance - sharesNeeded;
    }
}
