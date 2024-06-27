// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {console} from "@forge-std/console.sol";
import {ERC20} from "@solady/tokens/ERC20.sol";
import {ERC4626} from "@solady/tokens/ERC4626.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {TwabController} from "@pooltogether-v5-twab-controller/TwabController.sol";

// TODO: rewrite this as an ERC4626?
contract PointsToken is ERC20 {
    using SafeTransferLib for address;

    ERC4626 public immutable vault;

    /// @dev the vault **must** match the creating GameToken(msg.sender)'s vault!
    constructor(ERC4626 _vault) {
        vault = _vault;
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

    /// @notice make sure to approve the transfer of points before calling this function!
    function mint(address to, uint256 numPoints) public {
        vault.transferFrom(msg.sender, address(this), numPoints);

        _mint(to, numPoints);
    }

    function redeemPointsForVault(address player, uint256 numPoints) public {
        if (msg.sender != player) {
            _spendAllowance(msg.sender, player, numPoints);
        }

        _burn(player, numPoints);

        vault.transfer(player, numPoints);
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
}
