// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {ERC20} from "@solady/tokens/ERC20.sol";
import {ERC4626} from "@solady/tokens/ERC4626.sol";
import {GamePiece, GameToken} from "../public_goods/abstract/GamePiece.sol";
import {LibPRNG} from "@solady/utils/LibPRNG.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

contract GrimeDiceV0 is GamePiece {
    using SafeTransferLib for address;
    using LibPRNG for LibPRNG.PRNG;

    // TODO: NUM_COLORS is also numAssetTypes. gas golf
    uint256 public constant NUM_COLORS = 5;
    uint256 public constant NUM_SIDES = 6;
    uint8 public constant NUM_DICE_BAG = 10;

    event ChosenDice(address indexed player, uint256[NUM_DICE_BAG] dice);

    event Fees(
        address indexed player,
        uint256 devFundAmount,
        uint256 prizePoolShares,
        uint256 totalDiceValue,
        uint256 totalSponsorships
    );

    event SetMintDevFee(uint256 newFee);
    event SetMintPrizeFee(uint256 newFee);

    // this is probably way too much data to emit, but we only expect this to be called off-chain so it should be okay
    // TODO: but wait. do we get logs out of eth_call. i think maybe we will need to return the data instead. hmm
    event SkirmishBags(uint256 draws, uint256[] diceBag0, uint256[] diceBag1);
    event SkirmishColor(
        uint256 color0,
        uint256 color1,
        uint16 round,
        uint256 side0,
        uint256 side1
    );
    event SkirmishPlayers(
        address indexed player0,
        address indexed player1,
        uint8 wins0,
        uint8 wins1,
        uint8 ties
    );

    string internal tokenURIPrefix;

    /// @notice we could just look-up odds in a table, but i think dice with pips are a lot more fun
    struct DieInfo {
        uint32[NUM_SIDES] pips;
        string name;
        string symbol;
    }

    /// @dev the index is the "color" of the die
    DieInfo[NUM_COLORS] public dice;

    /// @dev TODO: gas golf this
    struct PlayerInfo {
        uint256 minted;
        // // TODO: track this?
        // uint256 burned;
        // // TODO: how should we do this? we don't need it yet but a later version will
        // uint64 wins;
        // uint64 losses;
        // uint64 ties;

        // TODO: this is too simple. think more about this. probably have "tournament" contracts with blinding and other cool things
        // TODO: the dice bags should be an ERC721 nft instead of a player only having one
        // TODO: let people use a contract to pick from the dice bag?
        uint256[NUM_DICE_BAG] chosenDice;
    }

    mapping(address => PlayerInfo) public players;

    /// TODO: how to do different prices for different vault tokens? once set, we can't change the refundPrice! but the other prices can change
    constructor(
        address _devFund,
        address _prizeFund,
        GameToken _gameToken,
        uint256 _redemptionPrice,
        uint256 _mintDevFee,
        uint256 _mintPrizeFee,
        uint256 _prngAge,
        string memory _tokenURIPrefix
    )
        GamePiece(
            _devFund,
            _gameToken,
            _mintDevFee,
            _mintPrizeFee,
            NUM_COLORS,
            _prngAge,
            _redemptionPrice
        )
    {
        devFund = _devFund;
        prizeFund = _prizeFund;
        mintDevFee = _mintDevFee;
        mintPrizeFee = _mintPrizeFee;
        tokenURIPrefix = _tokenURIPrefix;

        // TODO: are any approvals needed?
        // _gameToken.approve(address(_vaultToken), type(uint256).max);

        // grime dice
        // TODO: put this into calldata instead of hard coding it here
        // TODO: what about a "re-roll" face? -1?
        // TODO: how can we store these in an immutable?
        // taking this as calldata would be interesting, but the types get complicated
        dice[0] = DieInfo([uint32(4), 4, 4, 4, 4, 9], "Red", unicode"🟥");
        dice[1] = DieInfo([uint32(3), 3, 3, 3, 8, 8], "Yellow", unicode"⭐️");
        dice[2] = DieInfo([uint32(2), 2, 2, 7, 7, 7], "Blue", unicode"🔷");
        dice[3] = DieInfo([uint32(1), 1, 6, 6, 6, 6], "Magenta", unicode"💜");
        dice[4] = DieInfo([uint32(0), 5, 5, 5, 5, 5], "Olive", unicode"🫒");
    }

    function allDice() public view returns (DieInfo[NUM_COLORS] memory) {
        return dice;
    }

    /// TODO: do we want to somehow blind this until after the dice is buyDiceed? that would require more state
    /// this is here so that the game logic can upgrade but colors won't change
    /// @dev colors should NOT change with the version changing!
    function getColor(uint256 diceId) public pure returns (uint256) {
        return diceId % NUM_COLORS;
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return string(abi.encodePacked(tokenURIPrefix, id));
    }

    // TODO: is this a good name?
    function name(uint256 id) public view override returns (string memory) {
        DieInfo memory die = dice[getColor(id)];

        return string(abi.encodePacked(die.name, " Grime Die ", id));
    }

    function symbol(uint256 id) public view override returns (string memory) {
        DieInfo memory die = dice[getColor(id)];

        return string(abi.encodePacked("GD", die.symbol));
    }

    /// @notice the bag stays the same for 10 blocks
    function currentBag() public view returns (uint256[] memory bag) {
        LibPRNG.PRNG memory prng = prngTruncatedBlockNumber();

        bag = currentBag(prng, NUM_DICE_BAG);
    }

    /// @notice a random bag currently available for purchase
    function currentBag(
        LibPRNG.PRNG memory prng,
        uint256 numDice
    ) public pure returns (uint256[] memory bag) {
        (uint256[] memory diceIds, uint256[] memory diceAmounts) = randomPieces(
            prng,
            numDice,
            NUM_COLORS
        );

        uint256 numIds = diceIds.length;
        uint256 bagIndex = 0;
        bag = new uint256[](numDice);
        for (uint256 i = 0; i < numIds; i++) {
            uint256 currentId = diceIds[i];
            for (uint256 j = 0; j < diceAmounts[i]; j++) {
                bag[bagIndex] = currentId;
                bagIndex++;
            }
        }

        // TODO: does this shuffle matter? it probably isn't necessary, but shuffling is fun, right?
        prng.shuffle(bag);
    }

    // TODO: this is just to make off-chain calculations easy
    function scorePips(
        uint256[] memory pips0,
        uint256[] memory pips1
    ) public pure returns (uint256 wins0, uint256 wins1, uint256 ties) {
        uint256 numDice = pips0.length;

        require(numDice == pips1.length, "!len");

        wins0 = 0;
        wins1 = 0;
        ties = 0;

        for (uint256 i = 0; i < numDice; i++) {
            uint256 pip0 = pips0[i];
            uint256 pip1 = pips1[i];

            if (pip0 > pip1) {
                wins0++;
            } else if (pip1 > pip0) {
                wins1++;
            } else if (pip0 == pip1) {
                ties++;
            }
        }
    }

    function rollDice(
        LibPRNG.PRNG memory prng,
        uint256[] memory orderedDice
    ) public view returns (uint256[] memory pips) {
        // TODO: add something about the bag to the prng?

        uint256 bagSize = orderedDice.length;

        pips = new uint256[](bagSize);

        for (uint256 i = 0; i < bagSize; i++) {
            uint256 diceId = orderedDice[i];
            uint256 faceId = randomRoll(prng);

            uint256 colorId = getColor(diceId);

            DieInfo storage dieInfo = dice[colorId];

            pips[i] = dieInfo.pips[faceId];
        }
    }

    function rollCurrentBag() public view returns (uint256[] memory pips) {
        uint256[] memory bag = currentBag();

        LibPRNG.PRNG memory prng = skirmishPrng(address(this));

        pips = rollDice(prng, bag);
    }

    function rollPlayerBag(
        address player
    ) public view returns (uint256[] memory pips) {
        // copy the player's chosen dice into memory
        uint256[] memory bag = new uint256[](NUM_DICE_BAG);
        for (uint256 i = 0; i < NUM_DICE_BAG; i++) {
            bag[i] = players[player].chosenDice[i];
        }

        LibPRNG.PRNG memory prng = skirmishPrng(player);

        pips = rollDice(prng, bag);
    }

    /// @notice returns the faceId of a given die being rolled
    /// @dev TODO: think a lot more about this. include the diceId in here?
    function randomRoll(
        LibPRNG.PRNG memory prng
    ) public pure returns (uint256 faceId) {
        faceId = prng.next() % NUM_SIDES;
    }

    // TODO: how should we allow people to set their dice bags? let playerInfo approve another contract to do it. maybe just overload the operator on the NFT?
    function chooseDice(
        address player,
        uint256[NUM_DICE_BAG] calldata chosenDice
    ) public {
        // TODO: double check the order on isOperator
        require(
            player == msg.sender || isOperator(player, msg.sender),
            "!auth"
        );

        PlayerInfo storage playerInfo = players[player];

        // TODO: how can we make this support 150 dice types? maybe thats just too many to aim for in v1
        uint256[] memory counter = new uint256[](NUM_DICE_BAG);

        for (uint256 i = 0; i < NUM_DICE_BAG; i++) {
            playerInfo.chosenDice[i] = chosenDice[i];

            // i'd like to lock these dice, but that is a lot more complicated than i'd hoped at first (especially with upgrades)
            for (uint256 j = 0; j <= i; j++) {
                if (chosenDice[i] == chosenDice[j]) {
                    // if we've seen this dice before, increment the counter for that field
                    counter[i] += 1;
                    break;
                }
            }
        }

        for (uint256 i = 0; i < NUM_DICE_BAG; i++) {
            uint256 needed = counter[chosenDice[i]];

            if (needed > 0) {
                require(balanceOf(player, chosenDice[i]) >= needed, "!bal");
            }
        }

        emit ChosenDice(player, playerInfo.chosenDice);
    }

    // /// @notice the bag stays the same for 10 blocks
    // function buyNumDice(address receiver, uint256 numDice) public {
    //     require(numDice > 0, "!dice");

    //     uint256 priceWithFees_ = priceWithFees();

    //     uint256 cost = numDice * priceWithFees_;

    //     address(prizeToken).safeTransferFrom(msg.sender, address(this), cost);

    //     // deposit takes the amount of assets
    //     uint256 shares = vaultToken.deposit(cost, address(this));

    //     // we actually want the dice purchased to be predictable. i think that will be a fun mini-game for people
    //     LibPRNG.PRNG memory prng = numberPrng(block.number / 10);

    //     _buyDice(prng, receiver, numDice, shares, priceWithFees_);

    //     revert("move this fully to GamePiece.sol");
    // }

    function skirmishPrng(
        address player
    ) public view returns (LibPRNG.PRNG memory prng) {
        // TODO: i didn't think i'd need block.number here, but prevrandao wasn't changing like i expected. maybe on arbitrum it changes less often?
        prng.seed(
            uint256(
                keccak256(
                    abi.encodePacked(block.prevrandao, block.number, player)
                )
            )
        );
    }

    /*
     * Under construction...
     */

    // TODO: `battle` function that works like skirmish but is done with a secure commit-reveal scheme

    // TODO: recover 6909 tokens
}
