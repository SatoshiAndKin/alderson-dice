// SPDX-License-Identifier: GPL-3.0
// TODO: rewrite this to take the GameTokens as a way to purchase
// TODO: this needs to be an immutable contract. having the burn be part of the upgrade path is dangerous. at worst, only a week's prize money should be ruggable
pragma solidity 0.8.26;

import {ERC6909} from "@solady/tokens/ERC6909.sol";
import {Ownable} from "@solady/auth/Ownable.sol";
import {LibPRNG} from "@solady/utils/LibPRNG.sol";
import {GameToken, PointsToken} from "../GameToken.sol";

abstract contract GamePiece is ERC6909 {
    using LibPRNG for LibPRNG.PRNG;

    // TODO: these increase the gas cost noticeably, but i think we want this available on-chain
    uint256 public totalSupply;
    mapping(uint256 => uint256) public tokenSupply;

    GameToken public immutable gameToken;
    PointsToken public immutable pointsToken;

    uint256 public immutable buyPrice;
    address public immutable devFund;
    address public immutable prizeFund;
    uint256 public immutable mintDevFee;
    uint256 public immutable mintPrizeFee;
    uint256 public immutable numAssetTypes;
    uint256 public immutable prngAge;
    uint256 public immutable redemptionPrice;

    constructor(
        address _devFund,
        GameToken _gameToken,
        uint256 _mintDevFee,
        uint256 _mintPrizeFee,
        uint256 _numAssetTypes,
        uint256 _prngAge,
        uint256 _redemptionPrice
    ) {
        devFund = _devFund;
        gameToken = _gameToken;
        mintDevFee = _mintDevFee;
        mintPrizeFee = _mintPrizeFee;
        numAssetTypes = _numAssetTypes;
        prngAge = _prngAge;
        redemptionPrice = _redemptionPrice;

        buyPrice = redemptionPrice + mintDevFee + mintPrizeFee;

        require(buyPrice > 0, "zero buy price");

        pointsToken = _gameToken.pointsToken();
    }

    modifier decentralizedButtonPushing() {
        _;

        // TODO: put this in a try and ignore errors. we don't want to block the whole contract
        // TODO: only do if a certain amount of time has passed since the last time this was run
        // revert("forward earnings, claim points, etc.");
    }

    function buy(
        uint256 numPieces,
        address player
    ) public decentralizedButtonPushing returns (uint256 totalCost) {
        uint256 totalRedeemableValue = redemptionPrice * numPieces;
        uint256 totalMintDevFee = mintDevFee * numPieces;
        uint256 totalMintPrizeFee = mintPrizeFee * numPieces;

        totalCost = totalRedeemableValue + totalMintDevFee + totalMintPrizeFee;

        gameToken.transferFrom(msg.sender, address(this), totalCost);

        if (totalMintDevFee > 0) {
            gameToken.transfer(devFund, totalMintDevFee);
        }
        if (totalMintPrizeFee > 0) {
            // TODO: don't just transfer. if its a contract, call prizeFund.payFees(player, totalMintPrizeFee). this function awards points to the player
            gameToken.transfer(prizeFund, totalMintPrizeFee);
        }

        LibPRNG.PRNG memory prng = prngTruncatedBlockNumber();

        // TODO: blinded bag of pieces that is claimed in the future? i like the idea of predicting what you can buy though. blind random buys make me feel icky
        (
            uint256[] memory tokenIds,
            uint256[] memory tokenAmounts
        ) = randomPieces(prng, numPieces, numAssetTypes);

        _mintBulk(player, tokenIds, tokenAmounts);
    }

    // use the same prng for a range of blocks
    function prngTruncatedBlockNumber()
        public
        view
        returns (LibPRNG.PRNG memory prng)
    {
        return prngNumber(block.number / prngAge);
    }

    /// @dev TODO: THIS IS PREDICTABLE! KEEP THINKING ABOUT THIS
    /// I think predictable is fine for most of this game's random. I want players able to plan ahead some.
    function prngNumber(
        uint256 n
    ) public pure returns (LibPRNG.PRNG memory prng) {
        prng.seed(n);
    }

    /// @dev TODO: THIS IS PREDICTABLE (but not as easily as block number)! KEEP THINKING ABOUT THIS
    /// I think predictable is fine for most of this game's random. I want players able to plan ahead some.
    /// @dev TODO: include the player addresses? i dont actually think a player controlled seed input is a good idea
    function prngPrevrandao() public view returns (LibPRNG.PRNG memory prng) {
        prng.seed(uint256(block.prevrandao));
    }

    function randomPieces(
        LibPRNG.PRNG memory prng,
        uint256 numPieces,
        uint256 numTypes
    )
        public
        pure
        returns (uint256[] memory tokenIds, uint256[] memory amounts)
    {
        uint256 sum = 0;

        // TODO: this should actually be NUM_DICE.
        // TODO: modify this distribution so that dice in higher tiers are more rare?
        tokenIds = new uint256[](numTypes);
        amounts = new uint256[](numTypes);

        // Generate random values until the sum reaches or exceeds x
        // TODO: don't cap at numTypes. have multiple tiers of dice. maybe have seasons based on the mint week
        uint256 lastId = numTypes - 1;
        for (uint256 i = 0; i < lastId; i++) {
            // we increment by 1 so that "0" can be used a null value in mappings and lists (like the favorites list of a new account)
            tokenIds[i] = i + 1;

            if (tokenIds[i] == 0) {
                revert("bug 1");
            }

            uint256 remaining = numPieces - sum;

            amounts[i] = prng.uniform(remaining);
            sum += amounts[i];

            if (sum > numPieces) {
                revert("bug 2");
            }

            if (sum == numPieces) {
                break;
            }
        }

        // Assign the remaining value to the last element
        tokenIds[lastId] = lastId + 1;
        amounts[lastId] = numPieces - sum;

        // shuffling the tokenIds or the amounts should work equally well
        prng.shuffle(tokenIds);
    }

    /// @notice the player (or an operator) can sell their game pieces to recover their cost
    function sell(
        address player,
        uint256[] calldata diceIds,
        uint256[] calldata diceAmounts
    ) external decentralizedButtonPushing returns (uint256 refundAssets) {
        require(
            player == msg.sender || isOperator(player, msg.sender),
            "!auth"
        );

        uint256 length = diceIds.length;

        require(length == diceAmounts.length, "!len");

        uint256 burned = _burn(player, diceIds, diceAmounts);

        refundAssets = burned * redemptionPrice;

        gameToken.transfer(player, refundAssets);

        // playerInfo.burned += burned;
    }

    /// @dev be sure the underlying token has already been transferred here
    function _mintBulk(
        address receiver,
        uint256[] memory tokenIds,
        uint256[] memory amounts
    ) private returns (uint256 minted) {
        uint256 length = tokenIds.length;

        require(length == amounts.length, "length");

        uint256 id;
        uint256 amount;
        for (uint256 i = 0; i < length; i++) {
            amount = amounts[i];
            if (amount == 0) {
                continue;
            }

            id = tokenIds[i];
            require(id > 0, "zero");

            _mint(receiver, id, amount);

            tokenSupply[id] += amount;
            minted += amount;
        }

        // TODO: twab controller for keeping track of average balances?

        totalSupply += minted;
    }

    /// @dev this seems dangerous. be careful to not lock up any underlying assets!
    function _burn(
        address owner,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) private returns (uint256 burned) {
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

        // TODO: twab controller for keeping track of average balances?

        // TODO: handle the sending of funds back to to here?
    }
}
