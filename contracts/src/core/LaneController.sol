// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LaneControllerPausable} from "../security/Pausable.sol";
import {PrizeCalculator} from "../libraries/PrizeCalculator.sol";
import {LaneUtils} from "../libraries/LaneUtils.sol";
import {ILaneController} from "../interfaces/ILaneController.sol";
import {IReceiver} from "../interfaces/IReceiver.sol";
import {CreReportAuth} from "../libraries/CreReportAuth.sol";

/// @title LaneController
/// @notice Parimutuel multi-lane CCIP racing pool.
/// @dev Round lifecycle: Betting -> Racing -> Finished (winner declared) -> Settled.
///      Hops keep recording while Finished so the runner-up lane can complete.
///      Prize split (PrizeCalculator): 70% winner lane bettors, 15% platform,
///      10% gas reserve, 5% runner-up lane bettors. Winner/runner-up shares are
///      pull-based via `claimPrize`; shares with no eligible bettors go to the platform.
contract LaneController is LaneControllerPausable, ILaneController, IReceiver {
    using SafeERC20 for IERC20;

    enum RoundState {
        Betting,
        Racing,
        Finished,
        Settled
    }

    uint8 internal constant NO_LANE = type(uint8).max;

    struct Lane {
        uint64[] chainPath;
        uint8 hopsCompleted;
        uint8 requiredHops;
        uint256 totalLatency;
        uint256 finishTime;
        bool finished;
    }

    struct Round {
        RoundState state;
        uint8 laneCount;
        uint256 totalPrizePool;
        uint8 winningLaneId;
        uint8 runnerUpLaneId;
        bool winnerDeclared;
        bool prizesDistributed;
        uint256 winnerShare;
        uint256 runnerUpShare;
        uint256 winnerShareClaimed;
        uint256 runnerUpShareClaimed;
        mapping(uint8 => Lane) lanes;
        mapping(uint8 => mapping(address => uint256)) bets;
        mapping(uint8 => uint256) lanePool;
    }

    IERC20 public immutable bettingToken;
    address public creForwarder;
    address public platformTreasury;
    address public gasReserve;

    uint256 public currentRoundId;
    mapping(uint256 => Round) private s_rounds;
    mapping(address => bool) public hopRecorders;

    bool private _creReportActive;

    event RoundCreated(uint256 indexed roundId, uint8 laneCount);
    event BetPlaced(uint256 indexed roundId, uint8 indexed laneId, address indexed bettor, uint256 amount);
    event RaceStarted(uint256 indexed roundId);
    event HopCompleted(
        uint256 indexed roundId, uint8 indexed laneId, uint64 chainSelector, uint256 latency, uint8 hopIndex
    );
    event LaneFinished(uint256 indexed roundId, uint8 indexed laneId, uint256 finishTime);
    event WinnerDeclared(uint256 indexed roundId, uint8 indexed laneId, uint256 finishTime);
    event PrizesDistributed(uint256 indexed roundId, uint8 winnerLaneId, uint256 winnerPayout);
    event PrizeClaimed(uint256 indexed roundId, address indexed bettor, uint256 amount);

    error InvalidRound();
    error InvalidLane();
    error InvalidState();
    error InvalidAmount();
    error BettingClosed();
    error WinnerAlreadyDeclared();
    error NotAuthorized();
    error NoWinner();
    error AlreadySettled();
    error NotSettled();
    error NothingToClaim();
    error ReportExecutionFailed();
    error InvalidSendTime();

    uint256 internal constant MAX_HOP_LATENCY = 30 days;

    event UnclaimedSwept(uint256 indexed roundId, uint256 amount);

    modifier onlyRound(uint256 roundId) {
        if (roundId == 0 || roundId > currentRoundId) revert InvalidRound();
        _;
    }

    modifier onlyCreOrOwner() {
        if (!_creReportActive && msg.sender != creForwarder && msg.sender != owner()) {
            revert NotAuthorized();
        }
        _;
    }

    constructor(
        address initialOwner,
        address _bettingToken,
        address _platformTreasury,
        address _gasReserve,
        address _creForwarder
    ) LaneControllerPausable(initialOwner) {
        bettingToken = IERC20(_bettingToken);
        platformTreasury = _platformTreasury;
        gasReserve = _gasReserve;
        creForwarder = _creForwarder;
    }

    function setCreForwarder(address forwarder) external onlyOwner {
        creForwarder = forwarder;
    }

    /// @inheritdoc IReceiver
    function onReport(bytes calldata, bytes calldata report) external whenNotPaused {
        if (msg.sender != creForwarder) revert NotAuthorized();
        CreReportAuth.assertLaneControllerReport(report);
        _creReportActive = true;
        (bool ok,) = address(this).call(report);
        _creReportActive = false;
        if (!ok) revert ReportExecutionFailed();
    }

    function setHopRecorder(address recorder, bool allowed) external onlyOwner {
        hopRecorders[recorder] = allowed;
    }

    function createRound(uint64[][] calldata lanePaths) external onlyCreOrOwner whenNotPaused returns (uint256 roundId) {
        require(lanePaths.length > 1 && lanePaths.length < type(uint8).max, "bad lane count");

        roundId = ++currentRoundId;
        Round storage round = s_rounds[roundId];
        round.state = RoundState.Betting;
        round.laneCount = uint8(lanePaths.length);
        round.winningLaneId = NO_LANE;
        round.runnerUpLaneId = NO_LANE;

        for (uint8 i = 0; i < round.laneCount; i++) {
            require(lanePaths[i].length > 0, "empty path");
            round.lanes[i].chainPath = lanePaths[i];
            round.lanes[i].requiredHops = LaneUtils.requiredHops(lanePaths[i]);
        }

        emit RoundCreated(roundId, round.laneCount);
    }

    function buyLaneTokens(uint256 roundId, uint8 laneId, uint256 amount)
        external
        onlyRound(roundId)
        whenNotPaused
    {
        if (amount == 0) revert InvalidAmount();

        Round storage round = s_rounds[roundId];
        if (round.state != RoundState.Betting) revert BettingClosed();
        if (laneId >= round.laneCount) revert InvalidLane();

        bettingToken.safeTransferFrom(msg.sender, address(this), amount);
        round.bets[laneId][msg.sender] += amount;
        round.lanePool[laneId] += amount;
        round.totalPrizePool += amount;

        emit BetPlaced(roundId, laneId, msg.sender, amount);
    }

    function startRace(uint256 roundId) external onlyCreOrOwner onlyRound(roundId) whenNotPaused {
        Round storage round = s_rounds[roundId];
        if (round.state != RoundState.Betting) revert InvalidState();
        round.state = RoundState.Racing;
        emit RaceStarted(roundId);
    }

    function recordHop(uint256 roundId, uint8 laneId, uint64 chainSelector, uint256 sendTime)
        external
        onlyRound(roundId)
        whenNotPaused
    {
        if (!hopRecorders[msg.sender]) revert NotAuthorized();
        if (sendTime > block.timestamp) revert InvalidSendTime();

        uint256 latency = block.timestamp - sendTime;
        if (latency > MAX_HOP_LATENCY) latency = MAX_HOP_LATENCY;

        Round storage round = s_rounds[roundId];
        // Finished still accepts hops so the runner-up lane can complete its circuit.
        if (round.state != RoundState.Racing && round.state != RoundState.Finished) revert InvalidState();
        if (laneId >= round.laneCount) revert InvalidLane();

        Lane storage lane = round.lanes[laneId];
        if (lane.finished) revert InvalidState();

        lane.hopsCompleted++;
        lane.totalLatency += latency;

        emit HopCompleted(roundId, laneId, chainSelector, latency, lane.hopsCompleted);

        if (lane.hopsCompleted >= lane.requiredHops) {
            lane.finished = true;
            lane.finishTime = block.timestamp;
            emit LaneFinished(roundId, laneId, lane.finishTime);

            if (!round.winnerDeclared) {
                round.winningLaneId = laneId;
                round.winnerDeclared = true;
                round.state = RoundState.Finished;
                emit WinnerDeclared(roundId, laneId, lane.finishTime);
            } else if (round.runnerUpLaneId == NO_LANE) {
                round.runnerUpLaneId = laneId;
            }
        }
    }

    function declareWinner(uint256 roundId, uint8 laneId) external onlyCreOrOwner onlyRound(roundId) whenNotPaused {
        Round storage round = s_rounds[roundId];
        if (round.winnerDeclared) revert WinnerAlreadyDeclared();
        if (laneId >= round.laneCount) revert InvalidLane();

        Lane storage lane = round.lanes[laneId];
        if (!lane.finished) revert InvalidState();

        round.winningLaneId = laneId;
        round.winnerDeclared = true;
        round.state = RoundState.Finished;
        emit WinnerDeclared(roundId, laneId, lane.finishTime);
    }

    function distributePrizes(uint256 roundId) external onlyCreOrOwner onlyRound(roundId) whenNotPaused {
        Round storage round = s_rounds[roundId];
        if (!round.winnerDeclared) revert NoWinner();
        if (round.prizesDistributed) revert AlreadySettled();

        round.prizesDistributed = true;
        round.state = RoundState.Settled;

        PrizeCalculator.Payout memory payout = PrizeCalculator.calculate(round.totalPrizePool);

        uint256 platformAmount = payout.platform;

        // Winner/runner-up shares stay in the contract for pull-based claims.
        // Shares with no eligible bettors fall through to the platform treasury.
        if (round.lanePool[round.winningLaneId] > 0) {
            round.winnerShare = payout.winner;
        } else {
            platformAmount += payout.winner;
        }

        if (round.runnerUpLaneId != NO_LANE && round.lanePool[round.runnerUpLaneId] > 0) {
            round.runnerUpShare = payout.runnerUp;
        } else {
            platformAmount += payout.runnerUp;
        }

        if (platformAmount > 0) bettingToken.safeTransfer(platformTreasury, platformAmount);
        if (payout.gasReserve > 0) bettingToken.safeTransfer(gasReserve, payout.gasReserve);

        emit PrizesDistributed(roundId, round.winningLaneId, round.winnerShare);
    }

    /// @notice Claim a bettor's pro-rata share of the winner and/or runner-up pools.
    function claimPrize(uint256 roundId) external onlyRound(roundId) whenNotPaused returns (uint256 amount) {
        Round storage round = s_rounds[roundId];
        if (!round.prizesDistributed) revert NotSettled();

        amount = _consumeClaim(round, round.winningLaneId, round.winnerShare);
        if (round.runnerUpLaneId != NO_LANE) {
            amount += _consumeClaim(round, round.runnerUpLaneId, round.runnerUpShare);
        }
        if (amount == 0) revert NothingToClaim();

        bettingToken.safeTransfer(msg.sender, amount);
        emit PrizeClaimed(roundId, msg.sender, amount);
    }

    function _consumeClaim(Round storage round, uint8 laneId, uint256 share) internal returns (uint256 amount) {
        uint256 bet = round.bets[laneId][msg.sender];
        if (bet == 0 || share == 0) return 0;
        round.bets[laneId][msg.sender] = 0;
        amount = (share * bet) / round.lanePool[laneId];
        if (laneId == round.winningLaneId) {
            round.winnerShareClaimed += amount;
        } else if (laneId == round.runnerUpLaneId) {
            round.runnerUpShareClaimed += amount;
        }
    }

    /// @notice Sweep unclaimed winner/runner-up shares to platform after settlement.
    function sweepUnclaimed(uint256 roundId) external onlyCreOrOwner onlyRound(roundId) whenNotPaused {
        Round storage round = s_rounds[roundId];
        if (!round.prizesDistributed) revert NotSettled();

        uint256 unclaimed = (round.winnerShare - round.winnerShareClaimed)
            + (round.runnerUpShare - round.runnerUpShareClaimed);
        if (unclaimed == 0) revert NothingToClaim();

        round.winnerShareClaimed = round.winnerShare;
        round.runnerUpShareClaimed = round.runnerUpShare;
        bettingToken.safeTransfer(platformTreasury, unclaimed);
        emit UnclaimedSwept(roundId, unclaimed);
    }

    function getRoundWinner(uint256 roundId) external view onlyRound(roundId) returns (uint8 winnerLaneId) {
        return s_rounds[roundId].winningLaneId;
    }

    function getRoundRunnerUp(uint256 roundId) external view onlyRound(roundId) returns (uint8 runnerUpLaneId) {
        return s_rounds[roundId].runnerUpLaneId;
    }

    function getLanePool(uint256 roundId, uint8 laneId) external view returns (uint256) {
        return s_rounds[roundId].lanePool[laneId];
    }

    function getBet(uint256 roundId, uint8 laneId, address bettor) external view returns (uint256) {
        return s_rounds[roundId].bets[laneId][bettor];
    }

    function getRoundState(uint256 roundId) external view returns (RoundState) {
        return s_rounds[roundId].state;
    }

    function getTotalPrizePool(uint256 roundId) external view returns (uint256) {
        return s_rounds[roundId].totalPrizePool;
    }

    function getLane(uint256 roundId, uint8 laneId)
        external
        view
        returns (
            uint64[] memory chainPath,
            uint8 hopsCompleted,
            uint8 requiredHops,
            uint256 totalLatency,
            uint256 finishTime,
            bool finished
        )
    {
        Lane storage lane = s_rounds[roundId].lanes[laneId];
        return (lane.chainPath, lane.hopsCompleted, lane.requiredHops, lane.totalLatency, lane.finishTime, lane.finished);
    }
}
