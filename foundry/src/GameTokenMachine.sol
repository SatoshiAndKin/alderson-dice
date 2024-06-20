// SPDX-License-Identifier: UNLICENSED
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
import {GameToken} from "./GameToken.sol";

/// @notice transform any ERC4626 vault token into a gamified tokens where the interest is sent to a contract that earns points
contract GameTokenMachine {
    event GameTokenCreated(address indexed token, address indexed vault, address indexed earnings);

    TwabController public immutable twabController;

    constructor(TwabController _twabController) {
        twabController = _twabController;
    }

    // TODO: should earnings be a list? maybe with a list for shares too? that seems like a common need
    // while we could let them choose a twab controller, this seems safer
    function createGameToken(ERC4626 vault, address earnings) public returns (GameToken) {
        // TODO: use LibClone for this to save gas. the token uses immutables though so we need to figure out clones with immutables
        // TODO: i don't think we want to allow a customizeable salt
        GameToken token = new GameToken{salt: bytes32(0)}(twabController, vault, earnings);

        emit GameTokenCreated(address(token), address(vault), earnings);

        return token;
    }
}