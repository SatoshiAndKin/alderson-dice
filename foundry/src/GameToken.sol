// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

// TODO: move most of the NFT logic here
// TODO: give tokens based on deposits. make sure someone depositing can't reduce someone else's withdraw
// TODO: factory contract to deploy our tokens for any vault tokens

import {ERC20} from "@solady/tokens/ERC20.sol";
import {ERC4626} from "@solady/tokens/ERC4626.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";

/// @notice transform any ERC4626 vault tokens into game tokens
contract GameTokenMachine {
    event GameTokenCreated(address indexed token, address indexed vault, address indexed earnings);

    // TODO: should earnings be a list? maybe with a list for shares too? that seems like a common need
    function createGameToken(ERC4626 vault, address earnings) public returns (address) {
        // TODO: use LibClone for this to save gas. the token uses immutables though so we need to figure out clones with immutables
        // TODO: i don't think we want to allow a customizeable salt
        GameToken token = new GameToken{salt: bytes32(0)}(vault, earnings);

        emit GameTokenCreated(address(token), address(vault), earnings);

        return address(token);
    }
}

contract GameToken is ERC20 {
    using SafeTransferLib for address;

    ERC4626 immutable public vault;
    uint8 immutable internal vaultDecimals;

    ERC20 immutable public asset;
    uint8 immutable internal assetDecimals;

    uint256 public totalTokenValue;

    address immutable public earningsAddress;

    constructor(ERC4626 _vault, address _earningsAddress) {
        vault = _vault;

        vaultDecimals = vault.decimals();

        asset = ERC20(vault.asset());
        assetDecimals = asset.decimals();

        earningsAddress = _earningsAddress;
    }

    function _constantNameHash() internal view override returns (bytes32 result) {
        return keccak256(bytes(name()));
    }

    function name() public view override returns (string memory) {
        // we could cache these, but these methods are mostly used off-chain and so this is fine
        return string(abi.encodePacked("Gamified ", asset.name()));
    }

    function symbol() public view override returns (string memory) {
        // we could cache this locally, but these methods are mostly used off-chain and so this is fine
        return string(abi.encodePacked("g", asset.symbol()));
    }

    function depositAsset(uint256 amount, address to) public returns (uint256 shares) {
        address(asset).safeTransferFrom(msg.sender, address(this), amount);

        // deposit takes the amount of assets
        shares = vault.deposit(amount, to);

        // update amount to cover any rounding errors
        // redeem takes the amount of shares
        amount = vault.previewRedeem(shares);

        // TODO: optional fees here?

        totalTokenValue += amount;

        _mint(to, amount);
    }

    function depositVault(uint256 shares, address to) public returns (uint256 amount) {
        vault.transferFrom(msg.sender, address(this), shares);

        // redeem takes the amount of shares
        amount = vault.previewRedeem(shares);

        // TODO: optional fees here?
        // casinos don't take fees on buying chips with cash, but what we are building is a bit different. still maybe better to only take money off interest

        totalTokenValue += amount;

        _mint(to, amount);
    }

    // redeems game tokens for the vault token
    // TODO: do we want vault token or asset token? need functions for both
    function withdrawAsset(uint256 tokenAmount, address to, address owner) public returns (uint256 shares) {
        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, tokenAmount);
        }
        _burn(owner, tokenAmount);

        // TODO: this feels wrong
        // withdraw takes the amount of assets and returns the number of shares burned
        shares = vault.withdraw(tokenAmount, to, owner);

        // TODO: calculate from the shares instead of re-using the amount?
        totalTokenValue -= tokenAmount;

        address(asset).safeTransfer(to, tokenAmount);
    }

    // this method is necessary if the vault has limited withdrawal capacity
    function withdrawVault(uint256 amount, address to, address owner) public returns (uint256 shares) {
        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, amount);
        }
        _burn(owner, amount);

        // calculate the amount of shares required for the withdrawal
        shares = vault.previewWithdraw(amount);

        // TODO: calculate from the shares instead of re-using the amount?
        totalTokenValue -= amount;

        // transfer the vault tokens rather than withdrawing
        vault.transfer(to, shares);
    }

    function excessShares() public view returns (uint256 amount) {
        uint256 vaultBalance = vault.balanceOf(address(this));

        uint256 sharesNeeded = vault.previewWithdraw(totalTokenValue);

        if (sharesNeeded <= vaultBalance) {
            return 0;
        }

        amount = sharesNeeded - vaultBalance;
    }

    function excessAssets() public view returns (uint256 amount) {
        amount = vault.previewRedeem(excessShares());
    }

    function forwardExcess() public returns (uint256 shares) {
        shares = excessShares();

        if (shares > 0) {
            // TODO: optionally do multiple transfers here based on some share math
            vault.transfer(earningsAddress, shares);
        }
    }
}