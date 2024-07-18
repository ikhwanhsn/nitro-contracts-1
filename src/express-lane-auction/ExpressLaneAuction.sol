// SPDX-License-Identifier: UNLICENSED
// CHRIS: TODO: choose sol version
pragma solidity ^0.8.9;

import "./Errors.sol";
import "./Events.sol";
import "./Balance.sol";
// CHRIS: TODO: why named imports?
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {AccessControlUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Bid} from "./Structs.sol";
import "../libraries/DelegateCallAware.sol";
import "./IExpressLaneAuction.sol";
import "./ELCRound.sol";

// CHRIS: TODO: do we wamt to include the ability to update the round time?
// 3. update the round time
//    * do this via 2 reads each time
//    * check if an update is there, if so use that if it's in the past
//    * needs to contain round number as well as other things

// CHRIS: TODO: go through all the functions and look for duplicate storage access

// CHRIS: TODO: switch to a more modern version of openzeppelin so that we can use disableInitializers in the constructor. Or put onlyDelegated on the initializer and set up proxies in the test
// CHRIS: TODO: decide if we will allow the round timing info to be updated, and all the stuff that comes with that
// CHRIS: TODO: list of problems due to having a future offset:
//              1. cant withdraw balance until rounds begin
//              2. test other functions to see how they behave before offset has been reached, is it correct to revert or do nothing or what?
// CHRIS: TODO: review what would happen if blackout start == bidding stage length

// CHRIS: TODO:
// do the following to e2e test whether the everyting works before the offset
// 1. before the offset
//    * do deposit
//    * initiate withdrawal
//    * fail finalize withdrawal ofc
//    * set reserve
//    * fail resolve
//    * check all of the getters return the expected amounts
// 2. during round 0
//    * same as above, except resolve is allowed during the correct period
//    * and setting reserve fails during correct period
//    * check all of the getters
// 3. during round 1
//    * same as above
// 4. during round 2
//    * same as above, but can finalize the withdrawal

// CHRIS: TODO:
// also look at every function that uses the offset? yes
// also everything that is set during the resolve - and find all usages of those
// wrap all those functions in good getters that have predicatable and easy to reason about return values
// consider what would happen if the offset is set to the future after some rounds have been resolved. Should be easy to reason about if we've done our job correctly
// ok, so we will allow an update in the following way
// 1. direct update of the round timing info
// 2. when doing this ensure that the current round number stays the same
// 3. will update the timings of this round and the next
//    which could have negative consequences - but these need to be pointed out in docs
//    I think this is better than the complexity of scheduling a future update

// CHRIS: TODO: balance notes:
// CHRIS: TODO: invariant: balance after <= balance before
// CHRIS: TODO: invariant: if balance after == 0 and balance before == 0, then round must be set to max
// CHRIS: TODO: tests for balanceOf, freeBalance and withdrawable balance
// CHRIS: TODO: test each of the getter functions and withdrawal functions for an uninitialized deposit, and for one that has been zerod out

// CHRIS: TODO: could we do the transfer just via an event? do we really need to be able to query this from the contract?

// CHRIS: TODO: list all the things that are not set in the following cases:
//              1. before we start
//              2. during a gap
//              3. normal before resolve of current round and after

// CHRIS: TODO: surface this info somehow?
// DEPRECATED: will be replaced by a more ergonomic interface
// function expressLaneControllerRounds() public view returns (ELCRound memory, ELCRound memory) {
//     return (latestResolvedRounds[0], latestResolvedRounds[1]);
// }

// CHRIS: TODO: check every place where we set in a struct and ensure it's storage, or we do properly set later

// CHRIS: TODO: update docs there and decide if we want to add an lower address check in case of ties

// CHRIS: TODO: test boundary conditions in round timing info lib: 0, biddingStageDuration, biddingStageDuration + resolvingStageDuration

// CHRIS: TODO: when we include updates we need to point out that roundTimestamps() are not
//              accurate for timestamps after the update timestamp - that will be a bit tricky wont it?
//              all round timing stuff needs reviewing if we include updates

// CHRIS: TODO: line up natspec comments

// CHRIS: TODO: round timing info tests

/// @title  ExpressLaneAuction
/// @notice The express lane allows a controller to submit undelayed transactions to the sequencer
///         The right to be the express lane controller are auctioned off in rounds, by an offchain auctioneer.
///         The auctioneer then submits the winning bids to this control to deduct funds from the bidders and register the winner
contract ExpressLaneAuction is IExpressLaneAuction, AccessControlUpgradeable, DelegateCallAware {
    using SafeERC20 for IERC20;
    using RoundTimingInfoLib for RoundTimingInfo;
    using BalanceLib for Balance;
    using ECDSA for bytes32;
    using LatestELCRoundsLib for ELCRound[2];

    /// @inheritdoc IExpressLaneAuction
    bytes32 public constant AUCTIONEER_ROLE = keccak256("AUCTIONEER");
    /// @inheritdoc IExpressLaneAuction
    bytes32 public constant MIN_RESERVE_SETTER_ROLE = keccak256("MIN_RESERVE_SETTER");
    /// @inheritdoc IExpressLaneAuction
    bytes32 public constant RESERVE_SETTER_ROLE = keccak256("RESERVE_SETTER");
    /// @inheritdoc IExpressLaneAuction
    bytes32 public constant BENEFICIARY_SETTER_ROLE = keccak256("BENEFICIARY_SETTER");

    /// @notice Round timing settings
    RoundTimingInfo private roundTimingInfo;

    /// @notice The balances of each address
    mapping(address => Balance) internal _balanceOf;

    /// @inheritdoc IExpressLaneAuction
    address public beneficiary;

    /// @inheritdoc IExpressLaneAuction
    IERC20 public biddingToken;

    /// @inheritdoc IExpressLaneAuction
    uint256 public reservePrice;

    /// @inheritdoc IExpressLaneAuction
    uint256 public minReservePrice;

    /// @dev    Recently resolved round information. Contains the two most recently resolved rounds
    ELCRound[2] private latestResolvedRounds;

    /// @inheritdoc IExpressLaneAuction
    function initialize(
        address _auctioneer,
        address _beneficiary,
        address _biddingToken,
        RoundTimingInfo memory _roundTimingInfo,
        uint256 _minReservePrice,
        address _roleAdmin,
        address _minReservePriceSetter,
        address _reservePriceSetter,
        address _beneficiarySetter
    ) public initializer onlyDelegated {
        if (address(_biddingToken) == address(0)) {
            revert ZeroBiddingToken();
        }
        biddingToken = IERC20(_biddingToken);

        beneficiary = _beneficiary;
        emit SetBeneficiary(address(0), _beneficiary);

        minReservePrice = _minReservePrice;
        emit SetMinReservePrice(uint256(0), _minReservePrice);

        reservePrice = _minReservePrice;
        emit SetReservePrice(uint256(0), _minReservePrice);

        if (_roundTimingInfo.reserveBlackoutStart > _roundTimingInfo.biddingStageDuration) {
            revert ReserveBlackoutStartTooLong();
        }
        roundTimingInfo = _roundTimingInfo;

        _grantRole(DEFAULT_ADMIN_ROLE, _roleAdmin);
        _grantRole(AUCTIONEER_ROLE, _auctioneer);
        _grantRole(MIN_RESERVE_SETTER_ROLE, _minReservePriceSetter);
        _grantRole(RESERVE_SETTER_ROLE, _reservePriceSetter);
        _grantRole(BENEFICIARY_SETTER_ROLE, _beneficiarySetter);
    }

    /// @inheritdoc IExpressLaneAuction
    function currentRound() public view returns (uint64) {
        return roundTimingInfo.currentRound();
    }

    // CHRIS: TODO: move these back to being roundtiminginfo()
    /// @inheritdoc IExpressLaneAuction
    function roundOffsetTimestamp() public view returns (uint64) {
        return roundTimingInfo.offsetTimestamp;
    }

    /// @inheritdoc IExpressLaneAuction
    function resolvingStageDuration() public view returns (uint64) {
        return roundTimingInfo.resolvingStageDuration;
    }

    /// @inheritdoc IExpressLaneAuction
    function biddingStageDuration() public view returns (uint64) {
        return roundTimingInfo.biddingStageDuration;
    }

    /// @inheritdoc IExpressLaneAuction
    function roundReserveBlackoutStart() public view returns (uint64) {
        return roundTimingInfo.reserveBlackoutStart;
    }

    /// @inheritdoc IExpressLaneAuction
    function roundDuration() public view returns (uint64) {
        return roundTimingInfo.roundDuration();
    }

    /// @inheritdoc IExpressLaneAuction
    function isBiddingStage() public view returns (bool) {
        return roundTimingInfo.isBiddingStage();
    }

    /// @inheritdoc IExpressLaneAuction
    function isResolvingStage() public view returns (bool) {
        return roundTimingInfo.isResolvingStage();
    }

    /// @inheritdoc IExpressLaneAuction
    function isReserveBlackout() public view returns (bool) {
        (ELCRound memory lastRoundResolved,) = latestResolvedRounds.latestELCRound();
        // CHRIS: TODO: why do we put round + 1?
        return roundTimingInfo.isReserveBlackout(lastRoundResolved.round);
    }

    /// @inheritdoc IExpressLaneAuction
    function roundTimestamps(uint64 round) public view returns (uint64, uint64) {
        return roundTimingInfo.roundTimestamps(round);
    }

    /// @inheritdoc IExpressLaneAuction
    function setBeneficiary(address newBeneficiary) external onlyRole(BENEFICIARY_SETTER_ROLE) {
        emit SetBeneficiary(beneficiary, newBeneficiary);
        beneficiary = newBeneficiary;
    }

    function _setReservePrice(uint256 newReservePrice) private {
        if (newReservePrice < minReservePrice) {
            revert ReservePriceTooLow(newReservePrice, minReservePrice);
        }

        emit SetReservePrice(reservePrice, newReservePrice);
        reservePrice = newReservePrice;
    }

    /// @inheritdoc IExpressLaneAuction
    function setMinReservePrice(uint256 newMinReservePrice)
        external
        onlyRole(MIN_RESERVE_SETTER_ROLE)
    {
        emit SetMinReservePrice(minReservePrice, newMinReservePrice);

        minReservePrice = newMinReservePrice;

        if (newMinReservePrice > reservePrice) {
            _setReservePrice(newMinReservePrice);
        }
    }

    /// @inheritdoc IExpressLaneAuction
    function setReservePrice(uint256 newReservePrice) external onlyRole(RESERVE_SETTER_ROLE) {
        if (isReserveBlackout()) {
            revert ReserveBlackout();
        }

        _setReservePrice(newReservePrice);
    }

    /// @inheritdoc IExpressLaneAuction
    function balanceOf(address account) public view returns (uint256) {
        return _balanceOf[account].balanceAtRound(currentRound());
    }

    /// @inheritdoc IExpressLaneAuction
    function withdrawableBalance(address account) public view returns (uint256) {
        // CHRIS: TODO: consider whether the whole balance of mapping and the round number should be in a lib together
        return _balanceOf[account].withdrawableBalanceAtRound(currentRound());
    }

    /// @inheritdoc IExpressLaneAuction
    function deposit(uint256 amount) external {
        _balanceOf[msg.sender].increase(amount);
        biddingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, amount);
    }

    /// @inheritdoc IExpressLaneAuction
    function initiateWithdrawal(uint256 amount) external {
        uint64 curRnd = currentRound();
        _balanceOf[msg.sender].initiateReduce(amount, curRnd);
        emit WithdrawalInitiated(msg.sender, amount, curRnd + 2);
    }

    /// @inheritdoc IExpressLaneAuction
    function finalizeWithdrawal() external {
        uint256 amountReduced = _balanceOf[msg.sender].finalizeReduce(currentRound());
        biddingToken.safeTransfer(msg.sender, amountReduced);
        // CHRIS: TODO: consider adding the following assertion - it's an invariant
        // CHRIS: TODO: Invariant: assert(withdrawableBalance(msg.sender) == 0);
        emit WithdrawalFinalized(msg.sender, amountReduced);
    }

    /// @dev Update local state to resolve an auction
    /// @param isMultiBid Where the auction should be resolved from multiple bids
    /// @param firstPriceBid The winning bid
    /// @param firstPriceBidder The winning bidder
    /// @param priceToPay The price that needs to be paid by the winner
    /// @param biddingInRound The round bidding is taking place in. This is not the round the bidding is taking place for, which is biddingInRound + 1
    function resolveAuction(
        bool isMultiBid,
        Bid calldata firstPriceBid,
        address firstPriceBidder,
        uint256 priceToPay,
        uint64 biddingInRound
    ) internal {
        // store that a round has been resolved
        uint64 biddingForRound = biddingInRound + 1;
        latestResolvedRounds.setResolvedRound(biddingForRound, firstPriceBid.expressLaneController);

        // first price bidder pays the beneficiary
        _balanceOf[firstPriceBidder].reduce(priceToPay, biddingInRound);
        biddingToken.transfer(beneficiary, priceToPay);

        // emit events so that the offchain sequencer knows a new express lane controller has been selected
        (uint64 roundStart, uint64 roundEnd) = roundTimingInfo.roundTimestamps(biddingForRound);
        emit SetExpressLaneController(
            biddingForRound, address(0), firstPriceBid.expressLaneController, roundStart, roundEnd
        );
        emit AuctionResolved(
            isMultiBid,
            biddingForRound,
            firstPriceBidder,
            firstPriceBid.expressLaneController,
            firstPriceBid.amount,
            priceToPay,
            roundStart,
            roundEnd
        );
    }

    /// @inheritdoc IExpressLaneAuction
    function getBidHash(uint64 _round, uint256 _amount, address _expressLaneController)
        public
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(block.chainid, address(this), _round, _amount, _expressLaneController)
        );
    }

    /// @notice Recover the signing address of the provided bid, and check that that address has enough funds to fulfil that bid
    ///         Returns the signing address
    /// @param bid The bid to recover the signing address of
    /// @param biddingForRound The round the bid is for the control of
    function recoverAndCheckBalance(Bid memory bid, uint64 biddingForRound)
        internal
        view
        returns (address, bytes32)
    {
        bytes32 bidHash = getBidHash(biddingForRound, bid.amount, bid.expressLaneController);
        address bidder = bidHash.toEthSignedMessageHash().recover(bid.signature);
        // always check that the bidder has a much as they're claiming
        if (balanceOf(bidder) < bid.amount) {
            revert InsufficientBalanceAcc(bidder, bid.amount, balanceOf(bidder));
        }

        return (bidder, bidHash);
    }

    /// @inheritdoc IExpressLaneAuction
    function resolveSingleBidAuction(Bid calldata firstPriceBid)
        external
        onlyRole(AUCTIONEER_ROLE)
    {
        if (!roundTimingInfo.isResolvingStage()) {
            revert NotResolvingStage();
        }

        if (firstPriceBid.amount < reservePrice) {
            revert ReservePriceNotMet(firstPriceBid.amount, reservePrice);
        }

        uint64 biddingInRound = currentRound();
        uint64 biddingForRound = biddingInRound + 1;
        (address firstPriceBidder,) = recoverAndCheckBalance(firstPriceBid, biddingForRound);

        resolveAuction(false, firstPriceBid, firstPriceBidder, reservePrice, biddingInRound);
    }

    /// @inheritdoc IExpressLaneAuction
    function resolveMultiBidAuction(Bid calldata firstPriceBid, Bid calldata secondPriceBid)
        external
        onlyRole(AUCTIONEER_ROLE)
    {
        if (!roundTimingInfo.isResolvingStage()) {
            revert NotResolvingStage();
        }

        // if the bids are the same amount and offchain mechanism will be used to choose the order and
        // therefore the winner. The auctioneer is trusted to make this choice correctly
        if (firstPriceBid.amount < secondPriceBid.amount) {
            revert BidsWrongOrder();
        }

        // second amount must be greater than or equal the reserve
        if (secondPriceBid.amount < reservePrice) {
            revert ReservePriceNotMet(secondPriceBid.amount, reservePrice);
        }

        uint64 biddingInRound = currentRound();
        uint64 biddingForRound = biddingInRound + 1;
        // check the signatures and balances of both bids
        // even the second price bid must have the balance it's claiming
        (address firstPriceBidder, bytes32 firstBidHash) =
            recoverAndCheckBalance(firstPriceBid, biddingForRound);
        (address secondPriceBidder, bytes32 secondBidHash) =
            recoverAndCheckBalance(secondPriceBid, biddingForRound);

        // The bidders must be different so that our balance check isnt fooled into thinking
        // that the same balance is valid for both the first and second bid
        if (firstPriceBidder == secondPriceBidder) {
            revert SameBidder();
        }

        // when bids have the same amount we break ties based on the bid hash
        // although we include equality in the check we know this isnt possible due
        // to the check above that ensures the first price bidder and second price bidder are different
        // CHRIS: TODO: update the spec to this hash
        if (
            firstPriceBid.amount == secondPriceBid.amount
                && uint256(keccak256(abi.encodePacked(firstPriceBidder, firstBidHash)))
                    <= uint256(keccak256(abi.encodePacked(secondPriceBidder, secondBidHash)))
        ) {
            revert TieBidsWrongOrder();
        }

        resolveAuction(true, firstPriceBid, firstPriceBidder, secondPriceBid.amount, biddingInRound);
    }

    /// @inheritdoc IExpressLaneAuction
    function transferExpressLaneController(uint64 round, address newExpressLaneController)
        external
    {
        // past rounds cannot be transferred
        uint64 curRnd = currentRound();
        if (round < curRnd) {
            revert RoundTooOld(round, curRnd);
        }

        // only resolved rounds can be transferred
        ELCRound storage resolvedRound = latestResolvedRounds.resolvedRound(round);

        address resolvedELC = resolvedRound.expressLaneController;
        if (resolvedELC != msg.sender) {
            revert NotExpressLaneController(round, resolvedELC, msg.sender);
        }

        resolvedRound.expressLaneController = newExpressLaneController;

        (uint64 start, uint64 end) = roundTimingInfo.roundTimestamps(round);
        emit SetExpressLaneController(
            round,
            resolvedELC,
            newExpressLaneController,
            start < uint64(block.timestamp) ? uint64(block.timestamp) : start,
            end
        );
    }
}
