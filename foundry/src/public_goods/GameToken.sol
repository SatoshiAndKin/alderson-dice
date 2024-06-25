// SPDX-License-Identifier: GPL-3.0
// TODO: i don't love the name. kind of like chips in a casino or nickles in an arcade
pragma solidity 0.8.26;

// TODO: move most of the NFT logic here
// TODO: give tokens based on deposits. make sure someone depositing can't reduce someone else's withdraw
// TODO: factory contract to deploy our tokens for any vault tokens

import {ERC20} from "@solady/tokens/ERC20.sol";
import {ERC4626} from "@solady/tokens/ERC4626.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {PointsToken} from "./PointsToken.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {TwabController} from "@pooltogether-v5-twab-controller/TwabController.sol";

// TODO: rewrite this as an ERC4626?
contract GameToken is ERC20 {
    using SafeTransferLib for address;

    // TODO: this tracks the balances, but ERC20 also tracks the balance. we should probably improve that
    TwabController public immutable twabController;

    ERC4626 public immutable vault;

    PointsToken public immutable pointsToken;

    ERC20 public immutable asset;
    uint8 internal immutable assetDecimals;

    uint256 public totalForwardedShares;
    uint256 public totalForwardedValue;

    address public immutable earningsAddress;
    uint32 internal immutable deployTimestamp;

    struct ForwardedEarnings {
        uint256 shares;
        uint256 amount;
    }
    mapping(uint256 => ForwardedEarnings) public forwardedEarningsByPeriod;

    mapping(address => uint256 lastClaimTimestamp) public playerClaims;

    constructor(
        ERC20 _asset,
        address _earningsAddress,
        TwabController _twabController,
        ERC4626 _vault
    ) {
        twabController = _twabController;

        vault = _vault;

        asset = _asset;
        assetDecimals = _asset.decimals();

        // TODO: use LibClone for PointsToken. the token uses immutables though so we need to figure out clones with immutables
        pointsToken = new PointsToken(asset, twabController);

        // used to optimize the initial claim
        deployTimestamp = uint32(block.timestamp);

        earningsAddress = _earningsAddress;
    }

    modifier decentralizedButtonPushing() {
        _;

        // TODO: put this in a try and ignore errors. we don't want to block the whole contract
        // TODO: only do if a certain amount of time has passed since the last time this was run
        // TODO: only do this if the vault share price has changed
        forwardEarnings();
    }

    /// @dev Hook that is called after any transfer of tokens.
    /// This includes minting and burning.
    /// TODO: Time-weighted average balance controller from pooltogether takes a uint96, not a uint256. this might cause problems
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (amount == 0) {
            return;
        }

        uint96 amount96 = SafeCastLib.toUint96(amount);

        // TODO: why does this revert?!
        if (from == address(0)) {
            // twabController.mint(to, amount96);
        } else if (to == address(0)) {
            // twabController.burn(from, amount96);
        } else {
            // twabController.transfer(from, to, amount96);
        }
    }

    /// @dev we don't control the vault and so name might change
    function _constantNameHash()
        internal
        view
        override
        returns (bytes32 result)
    {
        return keccak256(bytes(name()));
    }

    /// @dev we don't control the vault and so name might change
    function name() public view override returns (string memory) {
        // we could cache these, but these methods are mostly used off-chain and so this is fine
        return string(abi.encodePacked("Gamified ", asset.name()));
    }

    /// @dev we don't control the vault and so symbol might change
    function symbol() public view override returns (string memory) {
        // we could cache this locally, but these methods are mostly used off-chain and so this is fine
        return string(abi.encodePacked("g", asset.symbol()));
    }

    /// @notice the primary entrypoint for users to deposit their own assets
    function depositAsset(uint256 amount) public returns (uint256 shares) {
        return depositAsset(amount, msg.sender);
    }

    /// @notice deposit the sender's assets and give the game tokens `to` someone else
    function depositAsset(
        uint256 amount,
        address to
    ) public returns (uint256 redeemableAmount) {
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

        _mint(to, redeemableAmount);
    }

    // the primary function for users to deposit their already vaulted tokens
    function depositVault(
        uint256 shares
    ) public returns (uint256 redeemableAmount) {
        return depositVault(shares, msg.sender);
    }

    /// @notice take the sender's vault tokens and give the game tokens `to` someone else
    function depositVault(
        uint256 shares,
        address to
    ) public returns (uint256 redeemableAmount) {
        vault.transferFrom(msg.sender, address(this), shares);

        // redeem takes the amount of shares
        redeemableAmount = vault.previewRedeem(shares);

        // TODO: optional fees here?
        // casinos don't take fees on buying chips with cash, but what we are building is a bit different. still maybe better to only take money off interest

        _mint(to, redeemableAmount);
    }

    // TODO: how do you undo a sponsorship?
    function sponsor() public {
        twabController.sponsor(msg.sender);
    }

    /// @notice the primary function for users to exchange their game tokens for the originally deposited value
    function withdrawAsset(
        uint256 amount
    ) public decentralizedButtonPushing returns (uint256 shares) {
        return withdrawAsset(amount, msg.sender, msg.sender);
    }

    /// @notice redeems game tokens for the vault token
    // TODO: do we want vault token or asset token? need functions for both
    function withdrawAsset(
        uint256 amount,
        address to,
        address owner
    ) public decentralizedButtonPushing returns (uint256 shares) {
        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, amount);
        }
        _burn(owner, amount);

        // withdraw takes the amount of assets and returns the number of shares burned
        // TODO: is this the right addresses?
        shares = vault.withdraw(amount, address(this), address(this));

        // TODO: withdraw directly to `to`?
        address(asset).safeTransfer(to, amount);
    }

    function withdrawAssetAsVault(
        uint256 amount
    ) public decentralizedButtonPushing returns (uint256 shares) {
        return withdrawAssetAsVault(amount, msg.sender, msg.sender);
    }

    /// @notice this method is necessary if the vault has limited withdrawal capacity
    function withdrawAssetAsVault(
        uint256 amount,
        address to,
        address owner
    ) public decentralizedButtonPushing returns (uint256 shares) {
        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, amount);
        }
        _burn(owner, amount);

        // calculate the amount of shares required for the withdrawal. don't actually withdraw them
        shares = vault.previewWithdraw(amount);

        // transfer the vault tokens rather than withdrawing
        vault.transfer(to, shares);
    }

    function withdrawVault(
        uint256 shares
    ) public decentralizedButtonPushing returns (uint256 amount) {
        return withdrawVault(shares, msg.sender, msg.sender);
    }

    function withdrawVault(
        uint256 shares,
        address to,
        address owner
    ) public decentralizedButtonPushing returns (uint256 amount) {
        // redeem takes the amount of shares
        amount = vault.previewRedeem(shares);

        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, amount);
        }

        _burn(owner, amount);

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
            return 0;
        }

        shares = sharesNeeded - vaultBalance;
    }

    function excess() public view returns (uint256 shares, uint256 amount) {
        shares = excessShares();

        if (shares > 0) {
            amount = vault.previewRedeem(shares);
        }
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

        // TODO: the timestamp truncation/wrapping is handled inside the twab controller. but we need to make sure our contract handles that correctly, too
        uint256 period = twabController.getTimestampPeriod(block.timestamp);

        ForwardedEarnings storage periodEarnings = forwardedEarningsByPeriod[
            period
        ];

        periodEarnings.shares += shares;
        periodEarnings.amount += amount;

        // TODO: optionally do multiple transfers here based on some share math?
        // TODO: don't just transfer. call a deposit method? this should make it more secure against inflation attacks
        vault.transfer(earningsAddress, shares);

        // TODO: emit an event
    }

    // TODO: this is going to need a lot of thought. we need to make sure we don't allow people to claim multiple times in the same period
    function claimPoints(
        uint32 maxPeriods,
        address player
    ) public returns (uint256 points) {
        uint256 lastClaimTimestamp = uint32(playerClaims[player]);
        // if lastClaimTimestamp is 0, set it to the timestamp for the first week of rewards
        if (lastClaimTimestamp == 0) {
            lastClaimTimestamp = uint32(deployTimestamp);
        }

        // TODO: does this handle wrapping correctly? probably not
        uint256 period = twabController.getTimestampPeriod(lastClaimTimestamp);
        uint256 currentPeriod = twabController.getTimestampPeriod(
            block.timestamp
        );

        // TODO: is this a good way to re-use twab's periods?
        uint256 periodDuration = uint256(twabController.PERIOD_LENGTH());

        for (uint256 i = 0; i < maxPeriods; i++) {
            if (period >= currentPeriod) {
                // don't allow claiming the current period
                break;
            }

            ForwardedEarnings
                storage periodEarnings = forwardedEarningsByPeriod[period];

            // TODO: tests for how it handles wrapping!
            uint256 claimUpTo = lastClaimTimestamp + periodDuration;

            uint256 weightedBalance = twabController.getTwabBetween(
                address(this),
                player,
                lastClaimTimestamp,
                claimUpTo
            );
            uint256 weightedTotalSupply = twabController
                .getTotalSupplyTwabBetween(
                    address(this),
                    lastClaimTimestamp,
                    claimUpTo
                );

            points += FixedPointMathLib.fullMulDiv(
                periodEarnings.amount,
                weightedBalance,
                weightedTotalSupply
            );

            period += 1;
            lastClaimTimestamp = claimUpTo;
        }

        // update storage once after the loop
        playerClaims[player] = lastClaimTimestamp;

        pointsToken.mint(player, points);
    }
}
