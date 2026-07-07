// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LaneControllerPausable} from "../security/Pausable.sol";
import {PrizeCalculator} from "../libraries/PrizeCalculator.sol";
import {StandardTokenTransfer} from "../libraries/StandardTokenTransfer.sol";
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
///      Only standard ERC20 betting tokens are supported (no fee-on-transfer).
contract LaneController is LaneControllerPausable, ILaneController, IReceiver, ReentrancyGuard {
    using StandardTokenTransfer for IERC20;

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
        bool finished;
        uint256 totalLatency;
        uint256 finishTime;
    }

    struct Round {
        RoundState state;
        uint8 laneCount;
        uint8 winningLaneId;
        uint8 runnerUpLaneId;
        uint8 winnerPayoutLaneId;
        bool winnerDeclared;
        bool prizesDistributed;
        bool claimsSwept;
        uint48 settledAt;
        uint48 claimWindowSnapshot;
        uint48 runnerUpSettlementTimeoutSnapshot;
        uint256 totalPrizePool;
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
    address public primaryHopRecorder;

    uint48 public roundCooldown;
    uint48 public lastRoundCreatedAt;
    /// @notice Minimum bet per `buyLaneTokens` call; lanes below this are treated as empty for payout redirect.
    uint256 public minBet;
    /// @notice Seconds after the winner lane finishes before unclaimed shares may be swept.
    uint48 public claimWindow;
    /// @notice After the winner lane finishes, settlement may proceed without the runner-up lane.
    uint48 public runnerUpSettlementTimeout;

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
    error InvalidChainSelector();
    error ZeroAddress();
    error RoundCooldownActive(uint256 availableAt);
    error RunnerUpPending();
    error ClaimWindowActive();
    error ClaimsSwept();

    uint256 internal constant MAX_HOP_LATENCY = 30 days;
    uint256 public constant MAX_HOPS = 16;
    uint48 public constant DEFAULT_ROUND_COOLDOWN = 60 seconds;
    uint48 public constant DEFAULT_CLAIM_WINDOW = 7 days;
    uint48 public constant DEFAULT_RUNNER_UP_SETTLEMENT_TIMEOUT = 7 days;
    /// @dev Default 1 USDC for 6-decimal betting tokens.
    uint256 public constant DEFAULT_MIN_BET = 1e6;
    uint256 public constant MAX_CLOCK_SKEW = 15 minutes;

    event UnclaimedSwept(uint256 indexed roundId, uint256 amount);
    event RoundCooldownUpdated(uint48 cooldown);
    event ClaimWindowUpdated(uint48 window);
    event RunnerUpSettlementTimeoutUpdated(uint48 timeout);
    event MinBetUpdated(uint256 minBet);

    modifier onlyRound(uint256 roundId) {
        if (roundId == 0 || roundId > currentRoundId) revert InvalidRound();
        _;
    }

    modifier onlyCreOrOwner() {
        // onReport self-calls admin functions after CRE auth; only reachable via onReport.
        if (msg.sender != creForwarder && msg.sender != owner() && msg.sender != address(this)) {
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
        if (
            _bettingToken == address(0) || _platformTreasury == address(0) || _gasReserve == address(0)
                || _creForwarder == address(0)
        ) revert ZeroAddress();
        bettingToken = IERC20(_bettingToken);
        platformTreasury = _platformTreasury;
        gasReserve = _gasReserve;
        creForwarder = _creForwarder;
        roundCooldown = DEFAULT_ROUND_COOLDOWN;
        claimWindow = DEFAULT_CLAIM_WINDOW;
        runnerUpSettlementTimeout = DEFAULT_RUNNER_UP_SETTLEMENT_TIMEOUT;
        minBet = DEFAULT_MIN_BET;
    }

    function setMinBet(uint256 newMinBet) external onlyOwner {
        minBet = newMinBet;
        emit MinBetUpdated(newMinBet);
    }

    function setRoundCooldown(uint48 cooldown) external onlyOwner {
        roundCooldown = cooldown;
        emit RoundCooldownUpdated(cooldown);
    }

    function setClaimWindow(uint48 window) external onlyOwner {
        claimWindow = window;
        emit ClaimWindowUpdated(window);
    }

    function setRunnerUpSettlementTimeout(uint48 timeout) external onlyOwner {
        runnerUpSettlementTimeout = timeout;
        emit RunnerUpSettlementTimeoutUpdated(timeout);
    }

    function setCreForwarder(address forwarder) external onlyOwner {
        if (forwarder == address(0)) revert ZeroAddress();
        creForwarder = forwarder;
    }

    /// @inheritdoc IReceiver
    function onReport(bytes calldata, bytes calldata report) external whenNotPaused nonReentrant {
        if (msg.sender != creForwarder) revert NotAuthorized();
        CreReportAuth.assertLaneControllerReport(report);
        bytes4 selector = bytes4(report[:4]);
        if (selector == bytes4(keccak256("distributePrizes(uint256)"))) {
            _distributePrizes(abi.decode(report[4:], (uint256)));
            return;
        }
        if (selector == bytes4(keccak256("sweepUnclaimed(uint256)"))) {
            _sweepUnclaimed(abi.decode(report[4:], (uint256)));
            return;
        }
        (bool ok,) = address(this).call(report);
        if (!ok) revert ReportExecutionFailed();
    }

    function setHopRecorder(address recorder, bool allowed) external onlyOwner {
        if (allowed) {
            if (primaryHopRecorder != address(0) && primaryHopRecorder != recorder) {
                hopRecorders[primaryHopRecorder] = false;
            }
            primaryHopRecorder = recorder;
        } else if (primaryHopRecorder == recorder) {
            primaryHopRecorder = address(0);
        }
        hopRecorders[recorder] = allowed;
    }

    function createRound(uint64[][] calldata lanePaths) external onlyCreOrOwner whenNotPaused returns (uint256 roundId) {
        require(lanePaths.length > 1 && lanePaths.length < type(uint8).max, "bad lane count");

        uint256 availableAt = uint256(lastRoundCreatedAt) + roundCooldown;
        if (block.timestamp < availableAt) revert RoundCooldownActive(availableAt);
        lastRoundCreatedAt = uint48(block.timestamp);

        uint8 laneCount = uint8(lanePaths.length);
        roundId = ++currentRoundId;
        Round storage round = s_rounds[roundId];
        round.state = RoundState.Betting;
        round.laneCount = laneCount;
        round.winningLaneId = NO_LANE;
        round.runnerUpLaneId = NO_LANE;
        round.winnerPayoutLaneId = NO_LANE;

        for (uint8 i = 0; i < laneCount; i++) {
            uint64[] calldata path = lanePaths[i];
            require(path.length > 0, "empty path");
            require(path.length <= MAX_HOPS, "path too long");
            Lane storage lane = round.lanes[i];
            lane.chainPath = path;
            lane.requiredHops = uint8(path.length);
        }

        emit RoundCreated(roundId, laneCount);
    }

    function buyLaneTokens(uint256 roundId, uint8 laneId, uint256 amount)
        external
        onlyRound(roundId)
        whenNotPaused
    {
        if (amount == 0 || amount < minBet) revert InvalidAmount();

        Round storage round = s_rounds[roundId];
        if (round.state != RoundState.Betting) revert BettingClosed();
        if (laneId >= round.laneCount) revert InvalidLane();

        bettingToken.transferFromExact(msg.sender, address(this), amount);
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
        if (sendTime > block.timestamp + MAX_CLOCK_SKEW) revert InvalidSendTime();

        uint256 latency = sendTime > block.timestamp ? 0 : block.timestamp - sendTime;
        if (latency > MAX_HOP_LATENCY) latency = MAX_HOP_LATENCY;

        Round storage round = s_rounds[roundId];
        if (round.state != RoundState.Racing && round.state != RoundState.Finished) revert InvalidState();
        if (laneId >= round.laneCount) revert InvalidLane();

        Lane storage lane = round.lanes[laneId];
        if (lane.finished) revert InvalidState();
        uint8 hopsCompleted = lane.hopsCompleted;
        if (chainSelector != lane.chainPath[hopsCompleted]) revert InvalidChainSelector();

        hopsCompleted++;
        lane.hopsCompleted = hopsCompleted;
        lane.totalLatency += latency;

        emit HopCompleted(roundId, laneId, chainSelector, latency, hopsCompleted);

        if (hopsCompleted >= lane.requiredHops) {
            lane.finished = true;
            lane.finishTime = block.timestamp;
            emit LaneFinished(roundId, laneId, lane.finishTime);

            if (!round.winnerDeclared) {
                round.winningLaneId = laneId;
                round.winnerDeclared = true;
                round.runnerUpSettlementTimeoutSnapshot = runnerUpSettlementTimeout;
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
        round.runnerUpSettlementTimeoutSnapshot = runnerUpSettlementTimeout;
        round.state = RoundState.Finished;
        emit WinnerDeclared(roundId, laneId, lane.finishTime);
    }

    function distributePrizes(uint256 roundId) external onlyCreOrOwner onlyRound(roundId) whenNotPaused nonReentrant {
        _distributePrizes(roundId);
    }

    function _distributePrizes(uint256 roundId) internal onlyRound(roundId) {
        Round storage round = s_rounds[roundId];
        if (!round.winnerDeclared) revert NoWinner();
        if (round.prizesDistributed) revert AlreadySettled();
        if (!_runnerUpResolved(round)) revert RunnerUpPending();

        round.prizesDistributed = true;
        round.state = RoundState.Settled;
        round.settledAt = uint48(block.timestamp);
        round.claimWindowSnapshot = claimWindow;

        PrizeCalculator.Payout memory payout = PrizeCalculator.calculate(round.totalPrizePool);

        uint8 winningLaneId = round.winningLaneId;
        uint8 runnerUpLaneId = round.runnerUpLaneId;
        uint256 platformAmount = payout.platform;
        uint256 winnerShare;
        uint8 payoutLaneId = _winnerPayoutLane(round, winningLaneId);

        if (payoutLaneId != NO_LANE && _lanePoolEligible(round.lanePool[payoutLaneId])) {
            winnerShare = payout.winner;
            round.winnerShare = winnerShare;
            round.winnerPayoutLaneId = payoutLaneId;
        } else {
            platformAmount += payout.winner;
        }

        if (runnerUpLaneId != NO_LANE && _lanePoolEligible(round.lanePool[runnerUpLaneId])) {
            round.runnerUpShare = payout.runnerUp;
        } else {
            platformAmount += payout.runnerUp;
        }

        if (platformAmount > 0) bettingToken.transferExact(platformTreasury, platformAmount);
        if (payout.gasReserve > 0) bettingToken.transferExact(gasReserve, payout.gasReserve);

        emit PrizesDistributed(roundId, winningLaneId, winnerShare);
    }

    function claimPrize(uint256 roundId) external onlyRound(roundId) nonReentrant returns (uint256 amount) {
        Round storage round = s_rounds[roundId];
        if (!round.prizesDistributed) revert NotSettled();
        if (round.claimsSwept) revert ClaimsSwept();

        uint8 winnerPayoutLaneId = round.winnerPayoutLaneId;
        if (winnerPayoutLaneId == NO_LANE) {
            winnerPayoutLaneId = round.winningLaneId;
        }

        uint8 runnerUpLaneId = round.runnerUpLaneId;
        if (runnerUpLaneId != NO_LANE && winnerPayoutLaneId == runnerUpLaneId) {
            amount = _consumeDualShareClaim(round, winnerPayoutLaneId, round.winnerShare, round.runnerUpShare);
        } else {
            amount = _consumeClaim(round, winnerPayoutLaneId, round.winnerShare, true);
            if (runnerUpLaneId != NO_LANE) {
                amount += _consumeClaim(round, runnerUpLaneId, round.runnerUpShare, false);
            }
        }
        if (amount == 0) revert NothingToClaim();

        bettingToken.transferExact(msg.sender, amount);
        emit PrizeClaimed(roundId, msg.sender, amount);
    }

    function _consumeDualShareClaim(
        Round storage round,
        uint8 laneId,
        uint256 winnerShare,
        uint256 runnerUpShare
    ) internal returns (uint256 amount) {
        uint256 bet = round.bets[laneId][msg.sender];
        if (bet == 0) return 0;

        uint256 winnerRemaining = winnerShare - round.winnerShareClaimed;
        uint256 runnerUpRemaining = runnerUpShare - round.runnerUpShareClaimed;
        if (winnerRemaining == 0 && runnerUpRemaining == 0) return 0;

        uint256 lanePool = round.lanePool[laneId];
        uint256 winnerAmount;
        if (winnerShare > 0 && winnerRemaining > 0) {
            winnerAmount = (winnerShare * bet) / lanePool;
            if (winnerAmount > winnerRemaining) winnerAmount = winnerRemaining;
        }

        uint256 runnerUpAmount;
        if (runnerUpShare > 0 && runnerUpRemaining > 0) {
            runnerUpAmount = (runnerUpShare * bet) / lanePool;
            if (runnerUpAmount > runnerUpRemaining) runnerUpAmount = runnerUpRemaining;
        }

        amount = winnerAmount + runnerUpAmount;
        if (amount == 0) return 0;

        round.bets[laneId][msg.sender] = 0;
        round.winnerShareClaimed += winnerAmount;
        round.runnerUpShareClaimed += runnerUpAmount;
    }

    function _consumeClaim(Round storage round, uint8 laneId, uint256 share, bool isWinnerShare)
        internal
        returns (uint256 amount)
    {
        uint256 bet = round.bets[laneId][msg.sender];
        if (bet == 0 || share == 0) return 0;

        uint256 claimed = isWinnerShare ? round.winnerShareClaimed : round.runnerUpShareClaimed;
        uint256 remaining = share - claimed;
        if (remaining == 0) return 0;

        amount = (share * bet) / round.lanePool[laneId];
        if (amount > remaining) amount = remaining;
        if (amount == 0) return 0;

        round.bets[laneId][msg.sender] = 0;
        if (isWinnerShare) {
            round.winnerShareClaimed += amount;
        } else {
            round.runnerUpShareClaimed += amount;
        }
    }

    function sweepUnclaimed(uint256 roundId) external onlyCreOrOwner onlyRound(roundId) whenNotPaused nonReentrant {
        _sweepUnclaimed(roundId);
    }

    function _sweepUnclaimed(uint256 roundId) internal onlyRound(roundId) {
        Round storage round = s_rounds[roundId];
        if (!round.prizesDistributed) revert NotSettled();
        if (round.claimsSwept) revert ClaimsSwept();

        if (block.timestamp < round.settledAt + round.claimWindowSnapshot) revert ClaimWindowActive();

        uint256 winnerShare = round.winnerShare;
        uint256 runnerUpShare = round.runnerUpShare;
        uint256 unclaimed =
            (winnerShare - round.winnerShareClaimed) + (runnerUpShare - round.runnerUpShareClaimed);
        if (unclaimed == 0) revert NothingToClaim();

        round.winnerShareClaimed = winnerShare;
        round.runnerUpShareClaimed = runnerUpShare;
        round.claimsSwept = true;
        bettingToken.transferExact(platformTreasury, unclaimed);
        emit UnclaimedSwept(roundId, unclaimed);
    }

    function _runnerUpResolved(Round storage round) internal view returns (bool) {
        if (round.runnerUpLaneId != NO_LANE) return true;

        uint8 winner = round.winningLaneId;
        if (winner == NO_LANE) return false;

        uint256 deadline = round.lanes[winner].finishTime + round.runnerUpSettlementTimeoutSnapshot;
        bool timedOut = block.timestamp > deadline;

        for (uint8 i = 0; i < round.laneCount; ++i) {
            if (i == winner) continue;
            if (!round.lanes[i].finished && !timedOut) return false;
        }
        return true;
    }

    function _lanePoolEligible(uint256 pool) internal view returns (bool) {
        return pool >= minBet;
    }

    function _winnerPayoutLane(Round storage round, uint8 winningLaneId) internal view returns (uint8) {
        if (_lanePoolEligible(round.lanePool[winningLaneId])) return winningLaneId;

        uint8 bestLane = NO_LANE;
        uint256 bestPool;
        for (uint8 i = 0; i < round.laneCount; ++i) {
            if (i == winningLaneId) continue;
            uint256 pool = round.lanePool[i];
            if (_lanePoolEligible(pool) && pool > bestPool) {
                bestPool = pool;
                bestLane = i;
            }
        }
        return bestLane;
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
