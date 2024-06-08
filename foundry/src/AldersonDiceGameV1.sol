// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {ERC4626} from "@solady/tokens/ERC4626.sol";
import {Ownable} from "@solady/auth/Ownable.sol";
import {IGameLogic, AldersonDiceNFT, ERC20} from "./AldersonDiceNFT.sol";
import {LibPRNG} from "@solady/utils/LibPRNG.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

// TODO: use a delegatecall ugpradable contract here? that keeps approvals active and passes the state on. but sometimes passing the state on isn't what we want
// maybe this should be a 4626 vault too? i think its easier for all the yield to go to the prizeFund and that can decide how to distribute things
// better to have a "staking" contract for splitting the yield. some to devs. some to prizes. some to dice stakers
contract AldersonDiceGameV1 is IGameLogic, Ownable {
    using SafeTransferLib for address;
    using LibPRNG for LibPRNG.PRNG;

    uint256 public constant NUM_COLORS = 5;
    uint256 public constant NUM_SIDES = 6;
    uint8 public constant NUM_ROLLS = 10;
    uint8 public constant NUM_DICE_BAG = 12;

    event FavoriteDice(address indexed player, uint256[NUM_DICE_BAG] dice);

    event Fees(
        address indexed player,
        uint256 devFundAmount,
        uint256 prizePoolShares,
        uint256 totalDiceValue,
        uint256 totalSponsorships
    );

    event SetMintDevFee(uint256 newFee);
    event SetMintPrizeFee(uint256 newFee);

    event Sponsored(address indexed sender, address indexed account, uint256 amount, uint256 balance, uint256 total);

    AldersonDiceNFT public immutable nft;

    /// @notice the source of prizes for this game
    ERC4626 public immutable vaultToken;

    /// @notice this is looked up during construction. it is the vault token's asset
    /// User's can withdraw this token by burning their dice
    ERC20 public immutable prizeToken;

    uint256 public totalDiceValue = 0;

    /// @notice the amount of the prize token that can be withdrawn by sponsors (and the dev)
    /// any interest earned on this token while
    uint256 public totalSponsorships = 0;
    mapping(address who => uint256 withdrawable) public sponsorships;

    string internal tokenURIPrefix;
    address public devFund;
    address public prizeFund;

    /// @notice extra cost to mint a die. goes to the dev fund
    uint256 public mintDevFee;
    /// @notice extra cost to mint a die. goes directly to the prize pool
    uint256 public mintPrizeFee;

    /// @notice due to rounding of shares and the underlying token, this is an estimate. it should be close
    uint256 public immutable refundPrice;

    /// @notice we could just look-up odds in a table, but i think dice with pips are a lot more fun
    struct DieColor {
        uint32[NUM_SIDES] pips;
        string name;
        string symbol;
    }

    /// @dev the index is the "color" of the die
    DieColor[NUM_COLORS] public dice;

    /// @dev TODO: gas golf this
    struct PlayerInfo {
        uint256 minted;
        // // TODO: track this?
        // uint256 burned;
        // // TODO: how should we do this? we don't need it yet but a later version will
        // uint64 wins;
        // uint64 losses;
        // uint64 ties;

        // TODO: the dice bags should be an ERC721 nft instead of a player only having one
        // TODO: this is too simple. think more about this. probably have "tournament" contracts with blinding and other cool things
        // TODO: let people use a contract to pick from the dice bag?
        uint256[NUM_DICE_BAG] favoriteDice;
    }

    mapping(address => PlayerInfo) public players;

    constructor(
        address _owner,
        address _devFund,
        address _prizeFund,
        AldersonDiceNFT _nft,
        ERC4626 _vaultToken,
        uint256 _refundPrice,
        uint256 _mintDevFee,
        uint256 _mintPrizeFee,
        string memory _tokenURIPrefix
    ) Ownable() {
        require(_refundPrice > 0, "!price");

        _initializeOwner(_owner);

        devFund = _devFund;
        prizeFund = _prizeFund;
        nft = _nft;
        vaultToken = _vaultToken;
        refundPrice = _refundPrice;
        mintDevFee = _mintDevFee;
        mintPrizeFee = _mintPrizeFee;
        tokenURIPrefix = _tokenURIPrefix;

        prizeToken = ERC20(vaultToken.asset());

        ERC20(prizeToken).approve(address(_vaultToken), type(uint256).max);

        // grime dice
        // TODO: put this into calldata instead of hard coding it here
        // TODO: what about a "re-roll" face? -1?
        // taking this as calldata would be interesting, but the types get complicated
        dice[0] = DieColor([uint32(4), 4, 4, 4, 4, 9], "Red", unicode"🟥");
        dice[1] = DieColor([uint32(3), 3, 3, 3, 8, 8], "Yellow", unicode"⭐️");
        dice[2] = DieColor([uint32(2), 2, 2, 7, 7, 7], "Blue", unicode"🔷");
        dice[3] = DieColor([uint32(1), 1, 6, 6, 6, 6], "Magenta", unicode"💜");
        dice[4] = DieColor([uint32(0), 5, 5, 5, 5, 5], "Olive", unicode"🫒");
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
        DieColor memory die = dice[color(id)];

        return string(abi.encodePacked(die.name, " Alderson Die"));
    }

    /// @notice there might be some rounding errors on this as tokens move through the vault
    function priceWithFees() public view returns (uint256) {
        return refundPrice + mintDevFee + mintPrizeFee;
    }

    function setMintDevFee(uint256 _fee) public onlyOwner {
        mintDevFee = _fee;

        emit SetMintDevFee(_fee);
    }

    function setMintPrizeFee(uint256 _fee) public onlyOwner {
        mintPrizeFee = _fee;

        emit SetMintPrizeFee(_fee);
    }

    function value(uint256 numDice) public view returns (uint256 refundAssets) {
        // get the supply before we burn
        uint256 totalSupply = nft.totalSupply();

        require(numDice <= totalSupply, "!supply");

        // some was given to the devFund and prizeFund. that introduces some rounding errors (and theres usually 1 wei rounding error too)
        refundAssets = FixedPointMathLib.fullMulDiv(totalDiceValue, numDice, totalSupply);
    }

    function symbol(uint256 id) public view virtual returns (string memory) {
        DieColor memory die = dice[color(id)];

        return string(abi.encodePacked("AD", die.symbol));
    }

    function upgrade(address _newGameLogic) public onlyOwner {
        nft.upgrade(_newGameLogic, true);
    }

    function setTokenURIPrefix(string memory _tokenURIPrefix) public onlyOwner {
        tokenURIPrefix = _tokenURIPrefix;
    }

    function currentBag() public view returns (uint256[] memory bag) {
        LibPRNG.PRNG memory prng = blockPrng();

        bag = currentBag(prng, NUM_DICE_BAG);
    }

    /// @notice a random bag currently available for purchase. this changes every block
    function currentBag(LibPRNG.PRNG memory prng, uint256 numDice) public pure returns (uint256[] memory bag) {
        (uint256[] memory diceIds, uint256[] memory diceAmounts) = randomDice(prng, numDice);

        bag = new uint256[](numDice);
        uint256 bagIndex = 0;

        uint256 numIds = diceIds.length;
        for (uint256 i = 0; i < numIds; i++) {
            for (uint256 j = 0; j < diceAmounts[i]; j++) {
                bag[bagIndex] = diceIds[i];
                bagIndex++;
            }
        }

        // TODO: does this shuffle matter? it probably isn't necessary, but shuffling is fun, right?
        prng.shuffle(bag);
    }

    // TODO: think more about this. 10 dice and 10 rounds is 100 rolls. is that too much?
    function skirmishColors(LibPRNG.PRNG memory prng, uint256 color0, uint256 color1, uint8 rounds)
        public view
        returns (uint8 wins0, uint8 wins1, uint8 ties)
    {
        DieColor memory dice0 = dice[color0];
        DieColor memory dice1 = dice[color1];

        for (uint16 round = 0; round < rounds; round++) {
            uint256 side0 = rollDie(prng);
            uint256 side1 = rollDie(prng);

            // // TODO: use console.log?
            // emit Pips(color0, dice0.pips, color1, dice1.pips);

            uint32 roll0 = dice0.pips[side0];
            uint32 roll1 = dice1.pips[side1];

            // // TODO: use console.log?
            // emit Skirmish(side0, side1, roll0, roll1);

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

    function skirmishBags(LibPRNG.PRNG memory prng, uint256[] memory diceBag0, uint256[] memory diceBag1, uint8 draws)
        public view
        returns (uint8 wins0, uint8 wins1, uint8 ties)
    {
        uint256 bagSize = diceBag0.length;

        require(bagSize == diceBag1.length, "Dice bags must be the same length");
        require(bagSize >= draws, "need more dice for this many draws");

        // randomize the dice
        // TODO: just shuffle one bag? with a good shuffle function, this is equivalent. its not nearly as fun to watch though
        prng.shuffle(diceBag0);
        prng.shuffle(diceBag1);

        for (uint256 i = 0; i < draws; i++) {
            uint256 color0 = color(diceBag0[i]);
            uint256 color1 = color(diceBag1[i]);

            // TODO: maybe we do want the diceId passed to this so we can use it for tie breaking or something
            (uint8 w0, uint8 w1,) = skirmishColors(prng, color0, color1, NUM_ROLLS);

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

    function skirmishPVE(LibPRNG.PRNG memory prng, address player)
        public
        view
        returns (uint8 wins0, uint8 wins1, uint8 ties)
    {
        PlayerInfo memory playerInfo = players[player];

        uint256[] memory diceBag1 = currentBag(prng, NUM_DICE_BAG);
        uint256[] memory diceBag0 = new uint256[](NUM_DICE_BAG);

        require(diceBag1.length == diceBag0.length, "bad bag size");

        for (uint256 i = 0; i < NUM_DICE_BAG; i++) {
            diceBag0[i] = playerInfo.favoriteDice[i];
        }

        (wins0, wins1, ties) = skirmishBags(prng, diceBag0, diceBag1, NUM_ROLLS);
    }

    /// @notice compare 2 player's favorite dice
    function skirmishPlayers(LibPRNG.PRNG memory prng, address player0, address player1)
        public view
        returns (uint8 wins0, uint8 wins1, uint8 ties)
    {
        uint256[] memory diceBag0 = new uint256[](NUM_DICE_BAG);
        uint256[] memory diceBag1 = new uint256[](NUM_DICE_BAG);

        for (uint256 i = 0; i < NUM_DICE_BAG; i++) {
            diceBag0[i] = players[player0].favoriteDice[i];
            diceBag1[i] = players[player1].favoriteDice[i];
        }

        (wins0, wins1, ties) = skirmishBags(prng, diceBag0, diceBag1, NUM_ROLLS);
    }

    /// @notice returns the faceId of a given die being rolled
    /// @dev TODO: think a lot more about this
    function rollDie(LibPRNG.PRNG memory prng) public pure returns (uint256 faceId) {
        faceId = prng.next() % NUM_SIDES;
    }

    function randomDice(LibPRNG.PRNG memory prng, uint256 numDice)
        public
        pure
        returns (uint256[] memory tokenIds, uint256[] memory amounts)
    {
        uint256 sum = 0;


        // TODO: this should actually be NUM_DICE.
        // TODO: modify this distribution so that dice in higher tiers are more rare?
        tokenIds = new uint256[](NUM_COLORS);
        amounts = new uint256[](NUM_COLORS);

        // Generate random values until the sum reaches or exceeds x
        // TODO: don't cap at NUM_COLORS. have multiple tiers of dice. maybe have seasons based on the mint week
        uint256 lastId = NUM_COLORS - 1;
        for (uint256 i = 0; i < lastId; i++) {
            // we increment by 1 so that "0" can be used a null value in mappings and lists (like the favorites list of a new account)
            tokenIds[i] = i + 1;

            if (tokenIds[i] == 0) {
                revert("bug 1");
            }

            uint256 remaining = numDice - sum;

            amounts[i] = prng.uniform(remaining);
            sum += amounts[i];

            if (sum > numDice) {
                revert("bug 2");
            }

            if (sum == numDice) {
                break;
            }
        }

        // Assign the remaining value to the last element
        tokenIds[lastId] = lastId + 1;
        amounts[lastId] = numDice - sum;

        prng.shuffle(tokenIds);
    }

    function _buyDice(LibPRNG.PRNG memory prng, address receiver, uint256 numDice, uint256 shares, uint256 _priceWithFees) internal {
        PlayerInfo storage playerInfo = players[receiver];

        playerInfo.minted += numDice;

        uint256 prizeFundShares = FixedPointMathLib.fullMulDiv(shares, mintPrizeFee, _priceWithFees);
        uint256 devFundShares = FixedPointMathLib.fullMulDiv(shares, mintDevFee, _priceWithFees);

        uint256 diceShares = shares - prizeFundShares - devFundShares;

        // handle any rounding errors
        uint256 newDiceValue = vaultToken.previewRedeem(diceShares);
        uint256 devFundAmount = vaultToken.previewRedeem(devFundShares);

        // the other half of the shares' value (with fixes for rounding errors) are given to the devFund
        // we keep them in the game to boost interest, but they can be withdrawn by the devFund at any time
        sponsorships[devFund] += devFundAmount;

        totalDiceValue += newDiceValue;
        totalSponsorships += devFundAmount;

        emit Fees(receiver, devFundAmount, prizeFundShares, totalDiceValue, totalSponsorships);

        // TODO: make this public so that a frame can easily show the current dice bag that is for sale
        (uint256[] memory diceIds, uint256[] memory diceAmounts) = randomDice(prng, numDice);

        nft.mint(receiver, diceIds, diceAmounts);
    }

    // TODO: how should we allow people to set their dice bags? let playerInfo approve another contract to do it. maybe just overload the operator on the NFT?
    function setDiceBag(address player, uint256[NUM_DICE_BAG] calldata favoriteDice) public {
        // TODO: double check the order on isOperator
        require(player == msg.sender || nft.isOperator(player, msg.sender), "!auth");

        PlayerInfo storage playerInfo = players[player];

        // TODO: how can we make this support 150 dice types? maybe thats just too many to aim for in v1
        uint256[] memory counter = new uint256[](NUM_DICE_BAG);

        for (uint256 i = 0; i < NUM_DICE_BAG; i++) {
            playerInfo.favoriteDice[i] = favoriteDice[i];

            // i'd like to transfer these dice out, but that is a lot more complicated than i'd hoped at first (especially with upgrades)
            for (uint256 j = 0; j <= i; j++) {
                if (favoriteDice[i] == favoriteDice[j]) {
                    // if we've seen this dice before, increment the counter for that field
                    counter[i] += 1;
                    break;
                }
            }
        }

        for (uint256 i = 0; i < NUM_DICE_BAG; i++) {
            uint256 needed = counter[favoriteDice[i]];

            if (needed > 0) {
                require(nft.balanceOf(player, favoriteDice[i]) >= needed, "!bal");
            }
        }

        emit FavoriteDice(player, playerInfo.favoriteDice);
    }

    function buyNumDice(address receiver, uint256 numDice) public {
        require(numDice > 0, "!dice");

        uint256 priceWithFees_ = priceWithFees();

        uint256 cost = numDice * priceWithFees_;

        address(prizeToken).safeTransferFrom(msg.sender, address(this), cost);

        // deposit takes the amount of assets
        uint256 shares = vaultToken.deposit(cost, address(this));

        LibPRNG.PRNG memory prng = blockPrng();

        _buyDice(prng, receiver, numDice, shares, priceWithFees_);
    }

    /// @notice the player (or an operator) can burn their dice to recover half the cost
    function returnDice(address player, uint256[] calldata diceIds, uint256[] calldata diceAmounts)
        external
        returns (uint256 refundAssets)
    {
        require(player == msg.sender || nft.isOperator(player, msg.sender), "!auth");

        uint256 length = diceIds.length;

        require(length == diceAmounts.length, "!len");

        // get the supply before we burn
        uint256 totalSupply = nft.totalSupply();

        uint256 burned = nft.burn(player, diceIds, diceAmounts);

        // some was given to the devFund and prizeFund. that introduces some rounding errors (and theres usually 1 wei rounding error too)
        refundAssets = FixedPointMathLib.fullMulDiv(totalDiceValue, burned, totalSupply);

        vaultToken.withdraw(refundAssets, player, address(this));

        totalDiceValue -= refundAssets;

        // playerInfo.burned += burned;
    }

    /// @dev TODO: THIS IS PREDICTABLE! KEEP THINKING ABOUT THIS
    /// I think predictable is fine for most of this game's random. I want players able to plan ahead some.
    function blockPrng() public view returns (LibPRNG.PRNG memory prng) {
        prng.seed(block.number);
    }

    /// @notice deposit tokens without minting any dice. all interest goes to the prize pool and dev fund.
    function sponsor(address account, uint256 amount) public returns (uint256 /*amount*/, uint256 shares) {
        address(prizeToken).safeTransferFrom(msg.sender, address(this), amount);

        // deposit takes the amount of assets
        shares = vaultToken.deposit(amount, address(this));

        // correct any rounding errors
        // redeem takes the amount of shares
        amount = vaultToken.previewRedeem(shares);

        require(amount > 0, "!amount");

        sponsorships[account] += amount;
        totalSponsorships += amount;

        emit Sponsored(msg.sender, account, amount, sponsorships[account], totalSponsorships);

        return (amount, shares);
    }

    /// @notice thank you for your sponsorship
    /// @dev todo? have an approval system for this?
    function endSponsership(address who, uint256 amount) public {
        require(who == msg.sender || nft.isOperator(who, msg.sender), "!auth");

        uint256 maxAmount = sponsorships[who];
        require(amount <= maxAmount, "!bal");

        uint256 shares = vaultToken.previewWithdraw(amount);
        require(shares > 0, "!shares");

        sponsorships[who] -= amount;
        totalSponsorships -= amount;

        // withdraw takes the amount of assets
        // we leave the shares in the vault because it saves gas and they can withdraw if they want to
        vaultToken.transfer(address(this), shares);
    }

    function prizeTokenAvailable() public view returns (uint256 available) {
        uint256 shares = prizeSharesAvailable();

        // redeem takes the amount of shares
        return vaultToken.previewRedeem(shares);
    }

    function prizeSharesAvailable() public view returns (uint256 prizeShares) {
        // 2 preview calls to handle rounding errors?
        // withdraw takes the amount of assets
        uint256 totalDiceShares = vaultToken.previewWithdraw(totalDiceValue);
        uint256 sponsorShares = vaultToken.previewWithdraw(totalSponsorships);

        uint256 ourShares = vaultToken.balanceOf(address(this));

        prizeShares = ourShares - totalDiceShares - sponsorShares;
    }

    function recover(address token, address to, uint256 amount) public {
        require(msg.sender == owner() || msg.sender == devFund);

        require(token != address(vaultToken), "!token");

        address(token).safeTransfer(to, amount);
    }

    /// @dev TODO: limit how often this can happen?
    /// @dev if the devFund wants a cut, that logic can be part of the prizeFund
    function sweepPrizeFund() public returns (uint256 shares) {
        shares = prizeSharesAvailable();

        if (shares > 0) {
            vaultToken.transfer(prizeFund, shares);
        }

        // TODO: i think in order to prevent some rounding attacks, we might actaully want prizeFund to pull the funds and do some math
    }

    /*
     * Under construction...
     */

    // TODO: `battle` function that works like skirmish but is done with a secure commit-reveal scheme

    // // a future contract will want this function. but we don't want it in V1
    // function release() public onlyOwner {
    //     _setOwner(address(0));
    // }

    // TODO: recover 6909 tokens
}
