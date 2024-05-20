// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {ERC20} from "@solady/tokens/ERC20.sol";
import {ERC6909} from "@solady/tokens/ERC6909.sol";
import {Ownable} from "@solady/auth/Ownable.sol";
import {LibBitmap} from "@solady/utils/LibBitmap.sol";
import {LibPRNG} from "@solady/utils/LibPRNG.sol";

// TODO: we need to write an

interface IGameLogic {
    function tokenURI(uint256 id) external view returns (string memory);
    function name(uint256 id) external view returns (string memory);
    function symbol(uint256 id) external view returns (string memory);
}

contract AldersonDiceNFT is ERC6909 {
    using LibPRNG for LibPRNG.PRNG;

    event Upgrade(address newGameLogic);

    IGameLogic public gameLogic;

    constructor(address _gameLogic) {
        gameLogic = IGameLogic(_gameLogic);
    }

    modifier onlyGameLogic() {
        require(msg.sender == address(gameLogic), "!auth");
        _;
    }

    function name(uint256 id) public view override returns (string memory) {
        return gameLogic.name(id);
    }

    function symbol(uint256 id) public view override returns (string memory) {
        return gameLogic.symbol(id);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return gameLogic.tokenURI(id);
    }

    function _beforeTokenTransfer(address, /*from*/ address, /*to*/ uint256, /*id*/ uint256 /*amount*/ )
        internal
        view
        override
    {
        // i don't think we need any checks here. we could maybe call into the game logic, but that adds a lot of gas
    }

    function _afterTokenTransfer(address, /*from*/ address, /*to*/ uint256, /*id*/ uint256 /*amount*/ )
        internal
        pure
        override
    {
        // i don't think we need any checks here. we could maybe call into the game logic, but that adds a lot of gas
    }

    // TODO: two-phase commit
    function upgrade(address _newGameLogic) external onlyGameLogic {
        gameLogic = IGameLogic(_newGameLogic);

        emit Upgrade(_newGameLogic);
    }

    function mint(address receiver, uint256[] calldata tokenIds, uint256[] calldata amounts) external onlyGameLogic {
        uint256 length = tokenIds.length;

        require(length == amounts.length, "length");

        for (uint256 i = 0; i < length; i++) {
            // TODO: safety check to make sure we aren't minting anything into token 0
            _mint(receiver, tokenIds[i], amounts[i]);
        }
    }

    // this seems dangerous
    function burn(address owner, uint256[] calldata tokenIds, uint256[] calldata amounts)
        external
        onlyGameLogic
        returns (uint256 burned)
    {
        uint256 length = tokenIds.length;

        require(length == amounts.length, "length");

        for (uint256 i = 0; i < length; i++) {
            _burn(owner, tokenIds[i], amounts[i]);

            burned += amounts[i];
        }
    }
}
