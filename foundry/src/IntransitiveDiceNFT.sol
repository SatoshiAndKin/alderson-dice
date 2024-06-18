// SPDX-License-Identifier: UNLICENSED
// TODO: rewrite this to take the GameTokens as a way to purchase
// TODO: this needs to be an immutable contract. having the burn be part of the upgrade path is dangerous. at worst, only a week's prize money should be ruggable
pragma solidity 0.8.26;

import {ERC20} from "@solady/tokens/ERC20.sol";
import {ERC6909} from "@solady/tokens/ERC6909.sol";
import {Ownable} from "@solady/auth/Ownable.sol";
import {LibPRNG} from "@solady/utils/LibPRNG.sol";

interface IGameLogic {
    function tokenURI(uint256 id) external view returns (string memory);
    function name(uint256 id) external view returns (string memory);
    function symbol(uint256 id) external view returns (string memory);
}

contract IntransitiveDiceNFT is ERC6909 {
    using LibPRNG for LibPRNG.PRNG;

    event Upgrade(
        address indexed sender, address indexed oldGameLogic, address indexed newGameLogic, bool allowOldBurn
    );

    IGameLogic public gameLogic;

    /// keep track of old game logic so that they can keep the ability to burn. otherwise tokens could be stuck!
    mapping(address => bool) public allowedBurners;

    // TODO: these increase the gas cost noticeably
    uint256 public totalSupply;
    mapping(uint256 => uint256) public tokenSupply;

    constructor(address _gameLogic) {
        gameLogic = IGameLogic(_gameLogic);
    }

    modifier onlyGameLogic() {
        require(msg.sender == address(gameLogic), "!auth");
        _;
    }

    modifier onlyBurners() {
        require(msg.sender == address(gameLogic) || allowedBurners[msg.sender], "!auth");
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
    function upgrade(address _newGameLogic, bool allowOldBurn) external onlyGameLogic {
        address oldGameLogic = address(gameLogic);

        // keep track of the old game logic so that it can still burn tokens
        // TODO: allow old game logic to remove itself once it is empty?
        if (allowOldBurn) {
            allowedBurners[oldGameLogic] = true;
        }

        gameLogic = IGameLogic(_newGameLogic);

        emit Upgrade(msg.sender, oldGameLogic, _newGameLogic, allowOldBurn);
    }

    function mint(address receiver, uint256[] calldata tokenIds, uint256[] calldata amounts)
        external
        onlyGameLogic
        returns (uint256 minted)
    {
        uint256 length = tokenIds.length;

        require(length == amounts.length, "length");

        uint256 id;
        uint256 amount;
        for (uint256 i = 0; i < length; i++) {
            id = tokenIds[i];
            amount = amounts[i];

            require(id > 0, "zero");

            if (amount == 0) {
                continue;
            }

            _mint(receiver, id, amount);

            tokenSupply[id] += amount;
            minted += amount;
        }

        totalSupply += minted;
    }

    /// @dev this seems dangerous. be careful to not lock up any underlying assets!
    function burn(address owner, uint256[] calldata tokenIds, uint256[] calldata amounts)
        external
        onlyBurners
        returns (uint256 burned)
    {
        uint256 length = tokenIds.length;

        require(length == amounts.length, "length");

        uint256 id;
        uint256 amount;
        for (uint256 i = 0; i < length; i++) {
            id = tokenIds[i];
            amount = amounts[i];

            if (amount > 0) {
                _burn(owner, id, amount);

                tokenSupply[id] -= amount;
                burned += amount;
            }
        }

        totalSupply -= burned;
    }
}