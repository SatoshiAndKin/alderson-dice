// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {ERC4626, ERC20} from "@solady/tokens/ERC4626.sol";
import {ERC6909} from "./abstract/ERC6909.sol";
import {Ownable} from "@solady/auth/Ownable.sol";
import {AldersonDiceNFT} from "./AldersonDiceNFT.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";

contract AldersonDiceGameV1 is Ownable {
    using SafeTransferLib for address;

    struct DieType {
        uint32[6] pips;
        string color;
    }

    struct Player {
        bool paid;
        uint256 wins;
        uint256 ties;
        uint256 losses;

        // TODO: this is too simple. think more about this. probably have "tournament" contracts with blinding and other cool things
        // TODO: let people use a contract to pick from the dice bag?
        uint256[10] diceBag;

    }

    event ScoreCard(string x);

    uint8 public constant NUM_COLORS = 5;
    uint8 public constant NUM_SIDES = 6;
    AldersonDiceNFT public immutable nft;

    ERC4626 public immutable vaultToken;
    ERC20 public immutable prizeToken;

    /// @notice rug prevention while still allowing upgrades during develoment
    bool public released;
    address public devFund;

    // TODO: store in an immutable instead?
    DieType[NUM_COLORS] public dice;

    // // TODO: tracking this on chain seems like too much state. but maybe we could use it for something. think more before adding this
    // struct Dice {
    //     uint256 wins;
    //     uint256 ties;
    //     uint256 losses;
    // }

    mapping(address => Player) public players;

    mapping(uint256 => DieType) public scoreCard;

    constructor(address _owner, AldersonDiceNFT _nft, ERC4626 _vaultToken) Ownable() {
        _initializeOwner(_owner);

        nft = _nft;
        vaultToken = _vaultToken;

        prizeToken = ERC20(vaultToken.asset());

        ERC20(prizeToken).approve(address(_vaultToken), type(uint256).max);

        dice[0] = DieType([uint32(4), 4, 4, 4, 4, 9], "red");
        dice[1] = DieType([uint32(3), 3, 3, 3, 8, 8], "yellow");
        dice[2] = DieType([uint32(2), 2, 2, 7, 7, 7], "blue");
        dice[3] = DieType([uint32(1), 1, 6, 6, 6, 6], "magenta");
        dice[4] = DieType([uint32(0), 5, 5, 5, 5, 5], "olive");
    }

    function resetApproval() public {
        address(prizeToken).safeApproveWithRetry(address(vaultToken), type(uint256).max);
    }

    // TODO: do we want to somehow blind this until after the dice is minted?
    // this is here so that the game logic can upgrade but colors won't change
    function color(uint256 tokenId) view public returns (uint8) {
        return uint8(uint256(keccak256(abi.encodePacked(address(nft), tokenId))) % NUM_COLORS);
    }

    function upgrade(address _newGameLogic) public onlyOwner {
        require(!released);

        nft.upgrade(_newGameLogic);
    }

    function release() public onlyOwner {
        _initializeOwner(address(0));
        released = true;
    }

    // TODO: think more about this. 10 dice and 10 rounds is 100 rolls. is that too much?
    function skirmish(bytes32 seed, uint256 dice0, uint256 dice1, uint8 rounds) public view returns (uint8 wins0, uint8 wins1, uint8 ties) {
        // if we put the color logic in this contract, then we can use most any compatible NFT 
        uint256 color0 = color(dice0);
        uint256 color1 = color(dice1);

        // TODO: do we want to copy into memory here? i think so
        DieType memory die0 = dice[color0];
        DieType memory die1 = dice[color1];

        for (uint16 round = 0; round < rounds; round++) {
            uint8 side0 = rollDie(seed, dice0, round);
            uint8 side1 = rollDie(seed, dice1, round);

            uint32 roll0 = die0.pips[side0];
            uint32 roll1 = die1.pips[side1];

            if (roll0 > roll1) {
                wins0++;
            } else if (roll1 > roll0) {
                wins1++;
            } else {
                ties++;
            }
        }
            
        // emit ScoreCard(scoreCard);
    }

    function skirmish(bytes32 seed, uint256[] memory diceBag0, uint256[] memory diceBag1, uint8 rounds) public view returns (uint8 wins0, uint8 wins1, uint8 ties) {
        require(diceBag0.length == diceBag1.length, "Dice bags must be the same length");

        for (uint8 i = 0; i < 10; i++) {
            uint256 dice0 = diceBag0[i];
            uint256 dice1 = diceBag1[i];

            (uint8 w0, uint8 w1, ) = skirmish(seed, dice0, dice1, rounds);

            if (w0 > w1) {
                wins0++;
            } else if (w1 > w0) {
                wins1++;
            } else {
                ties++;
            }
        }

        // emit ScoreCard(scoreCard);
    }

    function skirmish(bytes32 seed, address player0, address player1, uint8 rounds) public view returns (uint8 wins0, uint8 wins1, uint8 ties) {
        uint256[] memory diceBag0; 
        uint256[] memory diceBag1;

        for (uint8 i = 0; i < 10; i++) {
            diceBag0[i] = players[player0].diceBag[i];
            diceBag1[i] = players[player1].diceBag[i];
        }

        (wins0, wins1, ties) = skirmish(seed, diceBag0, diceBag1, rounds);
    }

    /// @notice returns the faceId of a given die being rolled
    /// @dev TODO: think a lot more about this
    function rollDie(bytes32 seed, uint256 dieId, uint16 round) public pure returns (uint8) {
        return uint8(uint256(keccak256(abi.encodePacked(seed, dieId, round))) % 6);
    }

    function mint(address receiver, uint256 amount) public {
        // TODO: what should price be?
        uint256 price = 0;

        uint256 cost = amount * price;

        address(prizeToken).safeTransferFrom(msg.sender, address(this), cost);

        uint256 shares = vaultToken.deposit(cost, address(this));

        // because of possible rounding errors. keep both "cost" and "half_cost" around
        // TODO: how much should we actually take? every other game takes 100%, so 50% seems like a good start to me
        uint256 half_shares = shares / 2;

        // TODO: keep track of share ownership here! some goes to the receiver, some goes to the dev fund

        nft.mint(receiver, amount);
    }

    // TODO: `battle` function that works like skirmish but is done with a secure commit-reveal scheme
}
