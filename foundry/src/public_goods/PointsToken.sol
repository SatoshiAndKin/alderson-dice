// SPDX-License-Identifier: GPL-3.0
// TODO: i don't love the name. kind of like chips in a casino or nickles in an arcade
pragma solidity 0.8.26;

// TODO: move most of the NFT logic here
// TODO: give tokens based on deposits. make sure someone depositing can't reduce someone else's withdraw
// TODO: factory contract to deploy our tokens for any vault tokens

import {ERC20} from "@solady/tokens/ERC20.sol";
import {ERC4626} from "@solady/tokens/ERC4626.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {TwabController} from "@pooltogether-v5-twab-controller/TwabController.sol";

contract PointsToken is ERC20 {
    address public immutable gameToken;
    ERC20 public immutable asset;

    // TODO: this tracks the balances, but ERC20 also tracks the balance. we should probably improve that
    TwabController public immutable twabController;

    constructor(ERC20 _asset, TwabController _twabController) {
        asset = _asset;
        gameToken = msg.sender;
        twabController = _twabController;
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
        return string(abi.encodePacked("Points from ", asset.name()));
    }

    /// @dev we don't control the vault and so symbol might change
    function symbol() public view override returns (string memory) {
        // we could cache this locally, but these methods are mostly used off-chain and so this is fine
        return string(abi.encodePacked("p", asset.symbol()));
    }

    function mint(address to, uint256 amount) public {
        require(msg.sender == gameToken);

        _mint(to, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    function burn(address owner, uint256 amount) public {
        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, amount);
        }

        _burn(owner, amount);
    }
}
