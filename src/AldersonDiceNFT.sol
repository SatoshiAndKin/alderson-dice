// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {ERC4626, ERC20} from "@solady/tokens/ERC4626.sol";
import {ERC6909} from "./abstract/ERC6909.sol";
import {Ownable} from "@solady/auth/Ownable.sol";


contract AldersonDiceNFT is ERC6909 {

    event Upgrade(address newGameLogic);

    address public gameLogic;
    uint256 public nextTokenId = 0;

    mapping(uint256 id => uint256 amount) public cooldowns;

    string public constant name = "AldersonDice";
    string public constant symbol = "AD";

    uint256 public immutable maxCooldownDelta;

    // TODO: baseUri?

    constructor(address _gameLogic, uint256 _maxCooldownDelta) {
        gameLogic = _gameLogic;
        maxCooldownDelta = _maxCooldownDelta;
    }

    function setCooldown(uint256 id, uint256 cooldown) external {
        require(msg.sender == gameLogic, "!auth");

        uint256 maxCooldown = block.timestamp + maxCooldownDelta;

        if (cooldown > maxCooldown) {
            cooldown = maxCooldown;
        }

        cooldowns[id] = cooldown;
    }

    function _preTransferCheck(address sender, uint256 tokenId, uint256 amount) internal override {
        require(cooldowns[tokenId] <= block.timestamp, "cooldown");
    }

    // TODO: two-phase commit
    function upgrade(address _newGameLogic) external {
        require(msg.sender == gameLogic, "!auth");

        emit Upgrade(_newGameLogic);

        gameLogic = _newGameLogic;
    }

    function mint(address receiver, uint256 amount) public {
        require(msg.sender == gameLogic, "!auth");

        for (uint256 i = 0; i < amount; i++) {
            // every dice is 1:1? then why do we need to keep track of the amount? seems like a waste of gas. maybe 6909 isn't the right standard
            _mint(receiver, nextTokenId++, 1);
        }
    }

    // this seems dangerous
    function burn(address owner, uint256[] calldata tokenIds) public {
        require(msg.sender == gameLogic, "!auth");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            _burn(owner, tokenIds[i], 1);
        }
    }
}
