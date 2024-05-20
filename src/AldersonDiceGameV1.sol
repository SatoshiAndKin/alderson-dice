// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {ERC4626} from "@solady/tokens/ERC4626.sol";
import {Ownable} from "@solady/auth/Ownable.sol";
import {IGameLogic, AldersonDiceNFT, ERC20} from "./AldersonDiceNFT.sol";
import {LibPRNG} from "@solady/utils/LibPRNG.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";

// maybe this should be a 4626 vault too? i think its easier for all the yield to go to the prizeFund and that can decide how to distribute things
// better to have a "staking" contract for splitting the yield. some to devs. some to prizes. some to dice stakers
contract AldersonDiceGameV1 is IGameLogic, Ownable {
    using SafeTransferLib for address;
    using LibPRNG for LibPRNG.PRNG;

    uint256 public constant NUM_COLORS = 5;
    uint256 public constant NUM_SIDES = 6;
    uint8 public constant NUM_ROUNDS = 10;
    uint8 public constant NUM_DICE_BAG = 12;

    string internal tokenURIPrefix;

    // we could just look-up odds in a table, but i think dice with pips are a lot more fun
    // TODO: be more consistent about "color" vs "type" vs "name"
    // the index is the "color" of the die
    struct DieInfo {
        uint32[NUM_SIDES] pips;
        string name;
        string symbol;
    }

    // TODO: gas golf this
    struct PlayerInfo {
        uint256 minted;
        // // TODO: track this?
        // uint256 burned;
        // // TODO: how should we do this? we don't need it yet but a later version will
        // uint64 wins;
        // uint64 losses;
        // uint64 ties;

        // TODO: the dice bags should be nfts instead of a player only having one
        // TODO: this is too simple. think more about this. probably have "tournament" contracts with blinding and other cool things
        // TODO: let people use a contract to pick from the dice bag?
        uint256[NUM_DICE_BAG] favoriteDice;
    }

    // // TODO: do we need to track these?
    // uint256 minted;
    // uint256 burned;

    event FavoriteDice(address player, uint256[NUM_DICE_BAG] dice);

    // event ScoreCard(string x);
    event Fees(address player, uint256 devFund, uint256 prizePool);

    // TODO: this should use console.log instead
    event Pips(uint256 color0, uint32[NUM_SIDES] pips0, uint256 color1, uint32[NUM_SIDES] pips1);

    // TODO: this should use console.log instead
    event Skirmish(uint256 side0, uint256 side1, uint32 roll0, uint32 roll1);

    AldersonDiceNFT public immutable nft;

    // TODO: function to set this
    uint256[NUM_DICE_BAG] public currentDrawing;

    /// @notice the source of prizes for this game
    ERC4626 public immutable vaultToken;

    /// @notice this is looked up during construction. it is the vault token's asset
    /// User's can withdraw this token by burning their dice
    ERC20 public immutable prizeToken;

    /// @notice the amount of the prize token that can be withdrawn
    /// any interest earned on this token while
    mapping(address who => uint256 withdrawable) public sponsorships;

    address public devFund;
    uint256 public immutable price;

    // TODO: store in an immutable instead?
    DieInfo[NUM_COLORS] public dieInfo;

    // // TODO: tracking this on chain seems like too much state. but maybe we could use it for something. think more before adding this
    // struct Dice {
    //     uint256 wins;
    //     uint256 ties;
    //     uint256 losses;
    // }

    mapping(address => PlayerInfo) public playerInfo;

    constructor(
        address _owner,
        address _devFund,
        AldersonDiceNFT _nft,
        ERC4626 _vaultToken,
        uint256 _price,
        string memory _tokenURIPrefix
    ) Ownable() {
        _initializeOwner(_owner);

        devFund = _devFund;
        nft = _nft;
        vaultToken = _vaultToken;
        price = _price;
        tokenURIPrefix = _tokenURIPrefix;

        prizeToken = ERC20(vaultToken.asset());

        ERC20(prizeToken).approve(address(_vaultToken), type(uint256).max);

        // grime dice
        // TODO: put this into calldata instead of hard coding it here
        // TODO: what about a "re-roll" face? -1?
        // taking this as calldata would be interesting, but the types get complicated
        dieInfo[0] = DieInfo([uint32(4), 4, 4, 4, 4, 9], "Red", unicode"🟥");
        dieInfo[1] = DieInfo([uint32(3), 3, 3, 3, 8, 8], "Yellow", unicode"⭐️");
        dieInfo[2] = DieInfo([uint32(2), 2, 2, 7, 7, 7], "Blue", unicode"🔷");
        dieInfo[3] = DieInfo([uint32(1), 1, 6, 6, 6, 6], "Magenta", unicode"💜");
        dieInfo[4] = DieInfo([uint32(0), 5, 5, 5, 5, 5], "Olive", unicode"🫒");
    }

    // this probably won't ever be needed, but just in case, anyone can set infinite approvals for the vault to take our prize tokens
    function fixGameApprovals() public {
        address(prizeToken).safeApproveWithRetry(address(vaultToken), type(uint256).max);
    }

    /// TODO: do we want to somehow blind this until after the dice is buyDiceed? that would require more state
    /// this is here so that the game logic can upgrade but colors won't change
    /// @dev colors should NOT change with the version changing!
    function color(uint256 diceId) public view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(address(nft), diceId))) % NUM_COLORS;
    }

    function tokenURI(uint256 id) public view returns (string memory) {
        return string(abi.encodePacked(tokenURIPrefix, id));
    }

    function name(uint256 id) external view returns (string memory) {
        DieInfo memory die = dieInfo[color(id)];

        return string(abi.encodePacked(die.name, " Alderson Die"));
    }

    function symbol(uint256 id) public view virtual returns (string memory) {
        DieInfo memory die = dieInfo[color(id)];

        return string(abi.encodePacked("AD", die.symbol));
    }

    function upgrade(address _newGameLogic) public onlyOwner {
        nft.upgrade(_newGameLogic);
    }

    function setTokenURIPrefix(string memory _tokenURIPrefix) public onlyOwner {
        tokenURIPrefix = _tokenURIPrefix;
    }

    // TODO: think more about this. 10 dice and 10 rounds is 100 rolls. is that too much?
    function skirmishColors(LibPRNG.PRNG memory seed, uint256 color0, uint256 color1, uint8 rounds)
        public
        returns (uint8 wins0, uint8 wins1, uint8 ties)
    {
        DieInfo memory dieInfo0 = dieInfo[color0];
        DieInfo memory dieInfo1 = dieInfo[color1];

        for (uint16 round = 0; round < rounds; round++) {
            uint256 side0 = rollDie(seed);
            uint256 side1 = rollDie(seed);

            emit Pips(color0, dieInfo0.pips, color1, dieInfo1.pips);

            uint32 roll0 = dieInfo0.pips[side0];
            uint32 roll1 = dieInfo1.pips[side1];

            // TODO: use console.log?
            emit Skirmish(side0, side1, roll0, roll1);

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

    function skirmishBags(LibPRNG.PRNG memory seed, uint256[] memory diceBag0, uint256[] memory diceBag1, uint8 rounds)
        public
        returns (uint8 wins0, uint8 wins1, uint8 ties)
    {
        uint256 bagSize = diceBag0.length;

        require(bagSize == diceBag1.length, "Dice bags must be the same length");
        require(bagSize >= rounds, "need more dice for this many rounds");

        // shuffle both sets of dice
        // TODO: just shuffle one bag? with a good shuffle function, this is equivalent
        seed.shuffle(diceBag0);
        // seed.shuffle(diceBag1);

        for (uint256 i = 0; i < rounds; i++) {
            uint256 color0 = color(diceBag0[i]);
            uint256 color1 = color(diceBag1[i]);

            // TODO: maybe we do want the diceId passed to this so we can use it for tie breaking or something
            (uint8 w0, uint8 w1,) = skirmishColors(seed, color0, color1, NUM_ROUNDS);

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

    function skirmishPVE(LibPRNG.PRNG memory prng, address player) public returns (uint8 wins0, uint8 wins1, uint8 ties) {
        PlayerInfo memory pi = playerInfo[player];
        
        uint256[] memory diceBag0 = new uint256[](NUM_DICE_BAG);
        uint256[] memory diceBag1 = new uint256[](NUM_DICE_BAG);

        for (uint256 i = 0; i < NUM_DICE_BAG; i++) {
            diceBag0[i] = pi.favoriteDice[i];
            diceBag1[i] = currentDrawing[i];
        }

        (wins0, wins1, ties) = skirmishBags(prng, diceBag0, diceBag1, NUM_ROUNDS);
    }

    /// @notice compare 2 player's favorite dice
    function skirmishPlayerInfos(LibPRNG.PRNG memory prng, address player0, address player1)
        public
        returns (uint8 wins0, uint8 wins1, uint8 ties)
    {
        uint256[] memory diceBag0 = new uint256[](NUM_DICE_BAG);
        uint256[] memory diceBag1 = new uint256[](NUM_DICE_BAG);

        for (uint256 i = 0; i < NUM_DICE_BAG; i++) {
            diceBag0[i] = playerInfo[player0].favoriteDice[i];
            diceBag1[i] = playerInfo[player1].favoriteDice[i];
        }

        (wins0, wins1, ties) = skirmishBags(prng, diceBag0, diceBag1, NUM_ROUNDS);
    }

    /// @notice returns the faceId of a given die being rolled
    /// @dev TODO: think a lot more about this
    function rollDie(LibPRNG.PRNG memory prng) public pure returns (uint256 faceId) {
        faceId = prng.next() % NUM_SIDES;
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
        uint256 lastId = NUM_COLORS - 1;
        for (uint256 i = 0; i < lastId; i++) {
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
        amounts[lastId] = numDice - sum;

        prng.shuffle(tokenIds);
    }

    function _buyDice(LibPRNG.PRNG memory prng, address receiver, uint256 numDice, uint256 cost, uint256 shares)
        internal
    {
        PlayerInfo storage player = playerInfo[receiver];

        player.minted += numDice;

        // half the shares are held for the player. dice can be burned to recover half the cost
        uint256 half_shares = shares / 2;
        uint256 half_cost = cost / 2;

        uint256 prizeFundAmount = half_cost / 2;
        uint256 prizeFundShares = half_shares / 2;

        uint256 devFundAmount = cost - half_cost - prizeFundAmount;

        // the other half of the shares (with fixes for rounding errors) are given to the devFund
        // we keep them in the game to boost interest, but they can be withdrawn by the devFund at any time
        // TODO: wait. if we track shares on this, then they don't
        sponsorships[devFund] += devFundAmount;

        // TODO: need to keep track of shares and cost here. that way sweeping the prize can have some

        emit Fees(receiver, devFundAmount, prizeFundAmount);

        (uint256[] memory diceIds, uint256[] memory diceAmounts) = _randomAmounts(prng, numDice);

        nft.mint(receiver, diceIds, diceAmounts);
    }

    // TODO: how should we allow people to set their dice bags? let playerInfo approve another contract to do it. maybe just overload the operator on the NFT?
    function setDiceBag(address _player, uint256[NUM_DICE_BAG] calldata dice) public {
        // TODO: double check the order on isOperator
        require(_player == msg.sender || nft.isOperator(_player, msg.sender), "!auth");

        PlayerInfo storage player = playerInfo[_player];

        // TODO: how can we make this support 150 dice types? maybe thats just too many to aim for in v1
        uint256[] memory counter = new uint256[](NUM_DICE_BAG);

        for (uint256 i = 0; i < NUM_DICE_BAG; i++) {
            player.favoriteDice[i] = dice[i];
            ++counter[dice[i]];
        }

        for (uint256 i = 0; i < NUM_DICE_BAG; i++) {
            require(nft.balanceOf(_player, dice[i]) > counter[dice[i]], "!bal");
        }

        emit FavoriteDice(_player, player.favoriteDice);
    }

    // TODO: check dice bag function

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

        LibPRNG.PRNG memory prng = blockPrng();

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

        LibPRNG.PRNG memory prng = blockPrng();

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

        LibPRNG.PRNG memory prng = blockPrng();

        _buyDice(prng, receiver, numDice, cost, shares);
    }

    /// @notice the player (or an operator) can burn their dice to recover half the cost
    function returnDice() external returns (uint256 refund) {
        revert("wip");
    }

    /// @dev TODO: THIS IS PREDICTABLE! KEEP THINKING ABOUT THIS
    function blockPrng() public view returns (LibPRNG.PRNG memory x) {
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
