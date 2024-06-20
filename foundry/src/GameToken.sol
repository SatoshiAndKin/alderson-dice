// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

// TODO: move most of the NFT logic here
// TODO: give tokens based on deposits. make sure someone depositing can't reduce someone else's withdraw
// TODO: factory contract to deploy our tokens for any vault tokens

import {ERC20} from "@solady/tokens/ERC20.sol";
import {ERC4626} from "@solady/tokens/ERC4626.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {TwabController} from "@pooltogether-v5-twab-controller/TwabController.sol";

/// @notice transform any ERC4626 vault tokens into game tokens
contract GameTokenMachine {
    event GameTokenCreated(address indexed token, address indexed vault, address indexed earnings);

    TwabController public immutable twabController;

    constructor(TwabController _twabController) {
        twabController = _twabController;
    }

    // TODO: should earnings be a list? maybe with a list for shares too? that seems like a common need
    function createGameToken(ERC4626 vault, address earnings) public returns (GameToken) {
        // TODO: use LibClone for this to save gas. the token uses immutables though so we need to figure out clones with immutables
        // TODO: i don't think we want to allow a customizeable salt
        GameToken token = new GameToken{salt: bytes32(0)}(twabController, vault, earnings);

        emit GameTokenCreated(address(token), address(vault), earnings);

        return token;
    }
}

contract GameToken is ERC20 {
    using SafeTransferLib for address;

    TwabController immutable public twabController;

    ERC4626 immutable public vault;
    uint8 immutable internal vaultDecimals;

    ERC20 immutable public asset;
    uint8 immutable internal assetDecimals;

    uint256 public totalForwardedShares;
    uint256 public totalForwardedValue;

    address immutable public earningsAddress;

    constructor(TwabController _twabController, ERC4626 _vault, address _earningsAddress) {
        twabController = _twabController;

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

    function depositAsset(uint256 amount) public returns (uint256 shares) {
        return depositAsset(amount, msg.sender);
    }

    function depositAsset(uint256 amount, address to) public returns (uint256 redeemableAmount) {
        address(asset).safeTransferFrom(msg.sender, address(this), amount);

        // exact approval every time is safer than infinite approval at start
        address(asset).safeApproveWithRetry(address(vault), amount);

        // deposit takes the amount of assets
        // the shares are minted to this contract. the `to` gets the GameToken ERC20 instead
        uint256 shares = vault.deposit(amount, address(this));

        // update amount to cover any rounding errors
        // redeem takes the amount of shares
        redeemableAmount = vault.previewRedeem(shares);

        // TODO: optional fees here?

        // TODO: Time-weighted average balance controller from pooltogether

        _mint(to, redeemableAmount);
    }

    function depositVault(uint256 shares) public returns (uint256 redeemableAmount) {
        return depositVault(shares, msg.sender);
    }

    /// @dev Hook that is called after any transfer of tokens.
    /// This includes minting and burning.
    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        uint96 amount96 = SafeCastLib.toUint96(amount);

        // TODO: Time-weighted average balance controller from pooltogether takes a uint96, not a uint256
        twabController.transfer(from, to, amount96);
    }

    function depositVault(uint256 shares, address to) public returns (uint256 redeemableAmount) {
        vault.transferFrom(msg.sender, address(this), shares);

        // redeem takes the amount of shares
        redeemableAmount = vault.previewRedeem(shares);

        // TODO: optional fees here?
        // casinos don't take fees on buying chips with cash, but what we are building is a bit different. still maybe better to only take money off interest


        _mint(to, redeemableAmount);
    }

    function withdrawAsset(uint256 amount) public returns (uint256 shares) {
        return withdrawAsset(amount, msg.sender, msg.sender);
    }

    // redeems game tokens for the vault token
    // TODO: do we want vault token or asset token? need functions for both
    function withdrawAsset(uint256 amount, address to, address owner) public returns (uint256 shares) {
        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, amount);
        }
        _burn(owner, amount);

        // TODO: Time-weighted average balance controller from pooltogether

        // withdraw takes the amount of assets and returns the number of shares burned
        // TODO: is this the right addresses?
        shares = vault.withdraw(amount, address(this), address(this));

        // TODO: withdraw directly to `to`?
        address(asset).safeTransfer(to, amount);
    }

    function withdrawAssetAsVault(uint256 amount) public returns (uint256 shares) {
        return withdrawAssetAsVault(amount, msg.sender, msg.sender);
    }

    /// @notice this method is necessary if the vault has limited withdrawal capacity
    function withdrawAssetAsVault(uint256 amount, address to, address owner) public returns (uint256 shares) {
        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, amount);
        }
        _burn(owner, amount);

        // TODO: Time-weighted average balance controller from pooltogether

        // calculate the amount of shares required for the withdrawal. don't actually withdraw them
        shares = vault.previewWithdraw(amount);

        // transfer the vault tokens rather than withdrawing
        vault.transfer(to, shares);
    }

    function withdrawVault(uint256 shares) public returns (uint256 amount) {
        return withdrawVault(shares, msg.sender, msg.sender);
    }

    function withdrawVault(uint256 shares, address to, address owner) public returns (uint256 amount) {
        // redeem takes the amount of shares
        amount = vault.previewRedeem(shares);

        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, amount);
        }

        _burn(owner, amount);

        // TODO: Time-weighted average balance controller from pooltogether

        // transfer the vault tokens rather than withdrawing
        vault.transfer(to, shares);
    }

    function excessShares() public view returns (uint256 shares) {
        uint256 vaultBalance = vault.balanceOf(address(this));

        if (vaultBalance == 0) {
            return shares;
        }

        uint256 totalTokenValue = totalSupply();

        if (totalTokenValue == 0) {
            return shares;
        }

        // withdraw takes the amount of assets and returns the number of shares burned
        uint256 sharesNeeded = vault.previewWithdraw(totalTokenValue);

        if (sharesNeeded <= vaultBalance) {
            return shares;
        }

        shares = sharesNeeded - vaultBalance;
    }

    function excess() public view returns (uint256 shares, uint256 amount) {
        shares = excessShares();

        amount = vault.previewRedeem(shares);
    }

    function forwardEarnings() public returns (uint256 shares, uint256 amount) {
        (shares, amount) = excess();

        if (shares == 0 || amount == 0) {
            return (0, 0);
        }

        // TODO: something similar to time-weighted average balancce controller from pooltogether
        // TODO: calculate the balance for the epoch. then we can combine the main TWABC balance with the value earned for the week
        totalForwardedShares += shares;
        totalForwardedValue += amount;

        // TODO: optionally do multiple transfers here based on some share math
        // TODO: don't just transfer. call a deposit method? this should make it more secure against inflation attacks
        vault.transfer(earningsAddress, shares);

        // TODO: emit an event
    }
}