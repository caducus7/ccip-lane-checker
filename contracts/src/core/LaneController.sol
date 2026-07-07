// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LaneControllerPausable} from "../security/Pausable.sol";
import {PrizeCalculator} from "../libraries/PrizeCalculator.sol";
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
        // hopsCompleted / requiredHops / finished share one slot.
        uint8 hopsCompleted;
        uint8 requiredHops;
        bool finished;
        uint256 totalLatency;
        uint256 finishTime;
    }

    struct Round {
        // All sub-word fields share one slot: created, declared and settled each
        // touch a single storage word instead of two.
        RoundState state;
        uint8 laneCount;
        uint8 winningLaneId;
        uint8 runnerUpLaneId;
        bool winnerDeclared;
        bool prizesDistributed;
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

    // Packed into one slot: rate-limit bookkeeping and the CRE re-entry flag.
    /// @notice Minimum seconds between `createRound` calls (0 disables the guard).
    uint48 public roundCooldown;
    /// @notice Timestamp of the last successful `createRound`.
    uint48 public lastRoundCreatedAt;
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
    error InvalidChainSelector();
    error ZeroAddress();
    error RoundCooldownActive(uint256 availableAt);

    uint256 internal constant MAX_HOP_LATENCY = 30 days;
    uint256 public constant MAX_HOPS = 16;
    /// @dev Anti-spam floor between rounds; owner-tunable via `setRoundCooldown`.
    uint48 public constant DEFAULT_ROUND_COOLDOWN = 60 seconds;

    event UnclaimedSwept(uint256 indexed roundId, uint256 amount);
    event RoundCooldownUpdated(uint48 cooldown);

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
        if (
            _bettingToken == address(0) || _platformTreasury == address(0) || _gasReserve == address(0)
                || _creForwarder == address(0)
        ) revert ZeroAddress();
        bettingToken = IERC20(_bettingToken);
        platformTreasury = _platformTreasury;
        gasReserve = _gasReserve;
        creForwarder = _creForwarder;
        roundCooldown = DEFAULT_ROUND_COOLDOWN;
    }

    /// @notice Sets the minimum interval between round creations. Zero disables the guard.
    function setRoundCooldown(uint48 cooldown) external onlyOwner {
        roundCooldown = cooldown;
        emit RoundCooldownUpdated(cooldown);
    }

    function setCreForwarder(address forwarder) external onlyOwner {
        if (forwarder == address(0)) revert ZeroAddress();
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

        // Rate limit: bounds round spam from a compromised CRE forwarder or owner key.
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

        for (uint8 i = 0; i < laneCount; i++) {
            uint64[] calldata path = lanePaths[i];
            require(path.length > 0, "empty path");
            require(path.length <= MAX_HOPS, "path too long");
            Lane storage lane = round.lanes[i];
            lane.chainPath = path;
            // Equivalent to LaneUtils.requiredHops without the calldata->memory copy;
            // length is bounded to (0, MAX_HOPS] above so the uint8 cast is safe.
            lane.requiredHops = uint8(path.length);
        }

        emit RoundCreated(roundId, laneCount);
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
        uint8 hopsCompleted = lane.hopsCompleted;
        // Hop N of a lane must land on the N-th chain of its configured path; a hop
        // recorder cannot credit progress with a selector outside the lane circuit.
        if (chainSelector != lane.chainPath[hopsCompleted]) revert InvalidChainSelector();

        // hopsCompleted < requiredHops <= MAX_HOPS, so the increment cannot overflow.
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

        uint8 winningLaneId = round.winningLaneId;
        uint8 runnerUpLaneId = round.runnerUpLaneId;
        uint256 platformAmount = payout.platform;
        uint256 winnerShare;

        // Winner/runner-up shares stay in the contract for pull-based claims.
        // Shares with no eligible bettors fall through to the platform treasury.
        if (round.lanePool[winningLaneId] > 0) {
            winnerShare = payout.winner;
            round.winnerShare = winnerShare;
        } else {
            platformAmount += payout.winner;
        }

        if (runnerUpLaneId != NO_LANE && round.lanePool[runnerUpLaneId] > 0) {
            round.runnerUpShare = payout.runnerUp;
        } else {
            platformAmount += payout.runnerUp;
        }

        if (platformAmount > 0) bettingToken.safeTransfer(platformTreasury, platformAmount);
        if (payout.gasReserve > 0) bettingToken.safeTransfer(gasReserve, payout.gasReserve);

        emit PrizesDistributed(roundId, winningLaneId, winnerShare);
    }

    /// @notice Claim a bettor's pro-rata share of the winner and/or runner-up pools.
    /// @dev Deliberately NOT `whenNotPaused`: a paused (or never-unpaused) contract must
    ///      not be able to freeze settled user funds.
    function claimPrize(uint256 roundId) external onlyRound(roundId) returns (uint256 amount) {
        Round storage round = s_rounds[roundId];
        if (!round.prizesDistributed) revert NotSettled();

        amount = _consumeClaim(round, round.winningLaneId, round.winnerShare, true);
        uint8 runnerUpLaneId = round.runnerUpLaneId;
        if (runnerUpLaneId != NO_LANE) {
            amount += _consumeClaim(round, runnerUpLaneId, round.runnerUpShare, false);
        }
        if (amount == 0) revert NothingToClaim();

        bettingToken.safeTransfer(msg.sender, amount);
        emit PrizeClaimed(roundId, msg.sender, amount);
    }

    function _consumeClaim(Round storage round, uint8 laneId, uint256 share, bool isWinnerShare)
        internal
        returns (uint256 amount)
    {
        uint256 bet = round.bets[laneId][msg.sender];
        if (bet == 0 || share == 0) return 0;
        round.bets[laneId][msg.sender] = 0;
        amount = (share * bet) / round.lanePool[laneId];
        if (isWinnerShare) {
            round.winnerShareClaimed += amount;
        } else {
            round.runnerUpShareClaimed += amount;
        }
    }

    /// @notice Sweep unclaimed winner/runner-up shares to platform after settlement.
    function sweepUnclaimed(uint256 roundId) external onlyCreOrOwner onlyRound(roundId) whenNotPaused {
        Round storage round = s_rounds[roundId];
        if (!round.prizesDistributed) revert NotSettled();

        uint256 winnerShare = round.winnerShare;
        uint256 runnerUpShare = round.runnerUpShare;
        uint256 unclaimed =
            (winnerShare - round.winnerShareClaimed) + (runnerUpShare - round.runnerUpShareClaimed);
        if (unclaimed == 0) revert NothingToClaim();

        round.winnerShareClaimed = winnerShare;
        round.runnerUpShareClaimed = runnerUpShare;
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
