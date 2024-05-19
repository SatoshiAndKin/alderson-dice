// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {ERC4626} from "@solady/tokens/ERC4626.sol";
import {Ownable} from "@solady/auth/Ownable.sol";
import {IGameLogic, AldersonDiceNFT, ERC20} from "./AldersonDiceNFT.sol";
import {LibPRNG} from "@solady/utils/LibPRNG.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";

contract AldersonDiceGameV1 is IGameLogic, Ownable {
    using SafeTransferLib for address;
    using LibPRNG for LibPRNG.PRNG;

    uint8 public constant NUM_COLORS = 5;
    uint8 public constant NUM_SIDES = 6;
    uint8 public constant NUM_ROUNDS = 10;
    uint8 public constant NUM_FAVORITES = 10;

    /// @notice after depositing funds, you have to wait this long before withdrawing. this is so that there is time for at least some interest to accrue
    uint256 public immutable withdrawalCooldown;
    string internal tokenURIPrefix;

    // we could just look-up odds in a table, but i think dice with pips are a lot more fun
    // TODO: be more consistent about "color" vs "type" vs "name"
    struct DieType {
        uint32[NUM_SIDES] pips;
        string name;
        string symbol;
    }

    // TODO: gas golf this
    struct Player {
        uint256 earliestWithdrawal;
        // // TODO: how should we do this? we don't need it yet but a later version will
        // uint64 wins;
        // uint64 losses;
        // uint64 ties;

        // TODO: the dice bags should be nfts instead of a player only having one
        // TODO: this is too simple. think more about this. probably have "tournament" contracts with blinding and other cool things
        // TODO: let people use a contract to pick from the dice bag?
        uint256[NUM_FAVORITES] favoriteDice;
    }

    // // TODO: do we need to track these?
    // uint256 minted;
    // uint256 burned;

    event FavoriteDice(address player, uint256[NUM_FAVORITES] dice);
    // event ScoreCard(string x);
    event DevFundDeposit(address purchaser, address devFund, uint256 amount);

    AldersonDiceNFT public immutable nft;

    // TODO: function to set this
    uint256[NUM_FAVORITES] public currentDrawing;

    /// @notice the source of prizes for this game
    ERC4626 public immutable vaultToken;

    /// @notice this is looked up during construction. it is the vault token's asset
    ERC20 public immutable prizeToken;

    /// @notice the amount of the prize token that can be withdrawn
    /// any interest earned on this token while
    mapping(address who => uint256 withdrawable) public sponsorships;

    address public devFund;
    uint256 public price;
    address public prizeFund;

    // TODO: store in an immutable instead?
    DieType[NUM_COLORS] public diceTypes;

    // // TODO: tracking this on chain seems like too much state. but maybe we could use it for something. think more before adding this
    // struct Dice {
    //     uint256 wins;
    //     uint256 ties;
    //     uint256 losses;
    // }

    mapping(address => Player) public players;

    constructor(
        address _owner,
        address _devFund,
        AldersonDiceNFT _nft,
        ERC4626 _vaultToken,
        uint256 _initialPrice,
        uint256 _withdrawalCooldown,
        string memory _tokenURIPrefix
    ) Ownable() {
        _initializeOwner(_owner);

        devFund = _devFund;
        nft = _nft;
        vaultToken = _vaultToken;
        price = _initialPrice;
        withdrawalCooldown = _withdrawalCooldown;
        tokenURIPrefix = _tokenURIPrefix;

        prizeToken = ERC20(vaultToken.asset());

        ERC20(prizeToken).approve(address(_vaultToken), type(uint256).max);

        // grime dice
        // TODO: put this into calldata instead of hard coding it here
        // TODO: what about a "re-roll" face? -1?
        diceTypes[0] = DieType([uint32(4), 4, 4, 4, 4, 9], "Red", unicode"🟥");
        diceTypes[1] = DieType([uint32(3), 3, 3, 3, 8, 8], "Yellow", unicode"⭐️");
        diceTypes[2] = DieType([uint32(2), 2, 2, 7, 7, 7], "Blue", unicode"🔷");
        diceTypes[3] = DieType([uint32(1), 1, 6, 6, 6, 6], "Magenta", unicode"💜");
        diceTypes[4] = DieType([uint32(0), 5, 5, 5, 5, 5], "Olive", unicode"🫒");
    }

    function resetApproval() public {
        address(prizeToken).safeApproveWithRetry(address(vaultToken), type(uint256).max);
    }

    // TODO: do we want to somehow blind this until after the dice is buyDiceed?
    // this is here so that the game logic can upgrade but colors won't change
    function color(uint256 diceId) public view returns (uint8) {
        return uint8(uint256(keccak256(abi.encodePacked(address(nft), diceId))) % NUM_COLORS);
    }

    function tokenURI(uint256 id) public view returns (string memory) {
        return string(abi.encodePacked(tokenURIPrefix, id));
    }

    function name(uint256 id) external view returns (string memory) {
        DieType memory die = diceTypes[color(id)];

        return string(abi.encodePacked(die.name, " Alderson Die"));
    }

    function symbol(uint256 id) public view virtual returns (string memory) {
        DieType memory die = diceTypes[color(id)];

        return string(abi.encodePacked("AD", die.symbol));
    }

    function upgrade(address _newGameLogic) public onlyOwner {
        nft.upgrade(_newGameLogic);
    }

    // TODO: think more about this. 10 dice and 10 rounds is 100 rolls. is that too much?
    function skirmish(LibPRNG.PRNG memory seed, uint256 color0, uint256 color1, uint8 rounds)
        public
        view
        returns (uint8 wins0, uint8 wins1, uint8 ties)
    {
        // TODO: do we want to copy into memory here? i think so
        DieType memory die0 = diceTypes[color0];
        DieType memory die1 = diceTypes[color1];

        for (uint16 round = 0; round < rounds; round++) {
            uint8 side0 = rollDie(seed);
            uint8 side1 = rollDie(seed);

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

    function skirmish(LibPRNG.PRNG memory seed, uint256[] memory diceBag0, uint256[] memory diceBag1, uint8 rounds)
        public
        view
        returns (uint8 wins0, uint8 wins1, uint8 ties)
    {
        require(diceBag0.length == diceBag1.length, "Dice bags must be the same length");

        for (uint8 i = 0; i < NUM_ROUNDS; i++) {
            uint256 color0 = color(diceBag0[i]);
            uint256 color1 = color(diceBag1[i]);

            // TODO: maybe we do want the diceId passed to this so we can use it for tie breaking or something
            (uint8 w0, uint8 w1,) = skirmish(seed, color0, color1, rounds);

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

    function skirmish(LibPRNG.PRNG memory prng, address player0, address player1, uint8 rounds)
        public
        view
        returns (uint8 wins0, uint8 wins1, uint8 ties)
    {
        uint256[] memory diceBag0;
        uint256[] memory diceBag1;

        for (uint8 i = 0; i < NUM_FAVORITES; i++) {
            diceBag0[i] = players[player0].favoriteDice[i];
            diceBag1[i] = players[player1].favoriteDice[i];
        }

        (wins0, wins1, ties) = skirmish(prng, diceBag0, diceBag1, rounds);
    }

    /// @notice returns the faceId of a given die being rolled
    /// @dev TODO: think a lot more about this
    function rollDie(LibPRNG.PRNG memory prng) public pure returns (uint8 faceId) {
        faceId = uint8(prng.next() % NUM_SIDES);
    }

    function _randomAmounts(LibPRNG.PRNG memory prng, uint256 numDice)
        internal
        pure
        returns (uint256[] memory tokenIds, uint256[] memory amounts)
    {
        uint256 sum = 0;

        tokenIds = new uint256[](NUM_COLORS);
        amounts = new uint256[](NUM_COLORS);

        // Generate random values until the sum reaches or exceeds x
        // TODO: don't cap at NUM_COLORS. have multiple tiers of dice
        for (uint256 i = 0; i < NUM_COLORS - 1; i++) {
            // we increment by 1 so that "0" can be used a null value in mappings and lists (like the favorites list of a new account)
            tokenIds[i] = i + 1;

            uint256 remaining = numDice - sum;

            amounts[i] = prng.uniform(remaining);
            sum += amounts[i];

            if (sum >= numDice) {
                break;
            }
        }

        // Assign the remaining value to the last element
        amounts[NUM_COLORS - 1] = numDice - sum;
    }

    function _buyDice(LibPRNG.PRNG memory prng, address receiver, uint256 numDice, uint256 cost, uint256 /*shares*/)
        internal
    {
        Player storage player = players[receiver];

        player.earliestWithdrawal = block.timestamp + withdrawalCooldown;

        // player.minted += numDice;

        // half the shares are held for the player. dice can be burned to recover half the cost
        // uint256 half_shares = shares / 2;
        uint256 half_cost = cost / 2;

        uint256 devFundAmount = cost - half_cost;

        // the other half of the shares (with fixes for rounding errors) are given to the devFund
        // we keep them in the game to boost interest, but they can be withdrawn by the devFund at any time
        // TODO: wait. if we track shares on this, then they don't
        sponsorships[devFund] += devFundAmount;

        // TODO: need to keep track of shares and cost here. that way sweeping the prize can have some

        emit DevFundDeposit(receiver, devFund, devFundAmount);

        (uint256[] memory diceIds, uint256[] memory diceAmounts) = _randomAmounts(prng, numDice);

        nft.mint(receiver, diceIds, diceAmounts);
    }

    // TODO: how should we allow people to set their dice bags? let players approve another contract to do it. maybe just overload the operator on the NFT?
    function setDiceBag(address _player, uint256[NUM_FAVORITES] calldata dice) public {
        require(_player == msg.sender || nft.isOperator(_player, msg.sender), "!auth");

        Player storage player = players[_player];

        // TODO: how can we make this support 150 dice types? maybe thats just too many to aim for in v1
        uint256[] memory deduped = new uint256[](NUM_COLORS);

        for (uint8 i = 0; i < NUM_FAVORITES; i++) {
            player.favoriteDice[i] = dice[i];
            ++deduped[dice[i]];
        }

        for (uint8 i = 0; i < NUM_FAVORITES; i++) {
            require(nft.balanceOf(_player, dice[i]) > deduped[dice[i]], "!bal");
        }

        emit FavoriteDice(_player, player.favoriteDice);
    }

    // TODO: check dice bag function

    // TODO: do something cool with a dutch auction?
    // TODO: support multiple vaults
    function setPrice(uint256 _price) public onlyOwner {
        price = _price;
    }

    function buyNumDice(address receiver, uint256 numDice) public {
        require(numDice > 0, "!dice");

        // no rounding errors are possible with this one
        uint256 cost = numDice * price;

        // TODO: this check is unnecessary except in dev
        uint256 shares;
        if (cost > 0) {
            address(prizeToken).safeTransferFrom(msg.sender, address(this), cost);

            shares = vaultToken.deposit(cost, address(this));
        } else {
            shares = 0;
        }

        LibPRNG.PRNG memory prng = insecurePrng();

        _buyDice(prng, receiver, numDice, cost, shares);
    }

    function buyDiceWithTotalCost(address receiver, uint256 cost) public {
        uint256 cachedPrice = price;

        uint256 numDice = cost / cachedPrice;

        require(numDice > 0, "!dice");

        // handle rounding errors. don't take excess
        cost = numDice * cachedPrice;

        // TODO: this check is unnecessary except in dev
        uint256 shares;
        if (cost > 0) {

            address(prizeToken).safeTransferFrom(msg.sender, address(this), cost);

            shares = vaultToken.deposit(cost, address(this));
        } else {
            shares = 0;
        }

        LibPRNG.PRNG memory prng = insecurePrng();

        _buyDice(prng, receiver, numDice, cost, shares);
    }

    /// @notice use this if you already have vault tokens
    function buyDiceWithVaultShares(address receiver, uint256 shares) public {
        uint256 cachedPrice = price;

        uint256 cost = vaultToken.convertToAssets(shares);

        // handle rounding errors. don't take excess
        cost -= (cost % cachedPrice);

        // update shares in case of excess
        shares = vaultToken.convertToShares(cost);

        // no rounding errors are possible thanks to checks above
        uint256 numDice = cost / cachedPrice;

        require(numDice > 0, "!dice");

        address(vaultToken).safeTransferFrom(msg.sender, address(this), shares);

        LibPRNG.PRNG memory prng = insecurePrng();

        _buyDice(prng, receiver, numDice, cost, shares);
    }

    // TODO: THIS IS PREDICTABLE! KEEP THINKING ABOUT THIS
    function insecurePrng() public view returns (LibPRNG.PRNG memory x) {
        x.seed(block.number);
    }

    // TODO: deposit tokens without mining any dice
    // function sponsor()

    // TODO: thank you for your sponsorship
    // function withdrawSponsership()

    // TODO: `battle` function that works like skirmish but is done with a secure commit-reveal scheme

    // // a future contract will want this function. but we don't want it in V1
    // function release() public onlyOwner {
    //     _setOwner(address(0));
    // }
}
