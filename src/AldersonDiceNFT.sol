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

    mapping(address owner => mapping (uint256 id => uint256 amount)) locked;

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

    function _beforeTokenTransfer(address from, address /*to*/, uint256 id, uint256 amount)
        internal
        view
        override
    {
        if (from == address(0)) {
            // mints don't need the lock check. thats just for user transfers
            return;
        }

        uint256 balance = balanceOf(from, id);
        uint256 needed = locked[from][id] + amount;

        require(needed <= balance, "lock");
    }

    function _afterTokenTransfer(address, /*from*/ address, /*to*/ uint256 id, uint256 /*amount*/ ) internal pure override {
        // i don't think we need any checks here
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
            _mint(receiver, tokenIds[i], amounts[i]);
        }
    }

    // this seems dangerous
    function burn(address owner, uint256[] calldata tokenIds, uint256[] calldata amounts) external onlyGameLogic {
        uint256 length = tokenIds.length;

        require(length == amounts.length, "length");

        for (uint256 i = 0; i < length; i++) {
            _burn(owner, tokenIds[i], amounts[i]);
        }
    }

    function lock(address owner, uint256[] calldata tokenIds, uint256[] calldata amounts) external onlyGameLogic {
        uint256 length = tokenIds.length;

        require(length == amounts.length, "length");

        for (uint256 i = 0; i < length; i++) {
           locked[owner][tokenIds[i]] += amounts[i];
        }
    }

    function unlock(address owner, uint256[] calldata tokenIds, uint256[] calldata amounts) external onlyGameLogic {
        uint256 length = tokenIds.length;

        require(length == amounts.length, "length");

        for (uint256 i = 0; i < length; i++) {
           locked[owner][tokenIds[i]] -= amounts[i];
        }
    }
}
