// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BroadcastScript} from "./BroadcastScript.sol";
import {LaneController} from "../src/core/LaneController.sol";
import {LaneExecutor} from "../src/core/LaneExecutor.sol";
import {ChainConfig} from "../src/libraries/ChainConfig.sol";

/// @title ManualParimutuelSmoke
/// @notice Owner-operated parimutuel smoke test (CRE substitute on testnet).
/// @dev Driven by `scripts/manual-parimutuel-smoke.sh` or direct env:
///
///      SMOKE_ACTION=setup|bet|start|send-next-hops|settle|claim|status
///      SMOKE_CHAIN=sepolia|arbitrum-sepolia|base-sepolia  (for send-next-hops)
///
///      forge script script/ManualParimutuelSmoke.s.sol:ManualParimutuelSmoke \
///        --rpc-url $SEPOLIA_RPC --account laneDeployer --sender $DEPLOYER --broadcast
contract ManualParimutuelSmoke is BroadcastScript {
    uint8 internal constant LANE_COUNT = 2;

    function run() external {
        string memory action = vm.envString("SMOKE_ACTION");
        bytes32 key = keccak256(bytes(action));

        if (key == keccak256("setup")) {
            _runSetup();
            return;
        }
        if (key == keccak256("bet")) {
            _runBet();
            return;
        }
        if (key == keccak256("start")) {
            _runStart();
            return;
        }
        if (key == keccak256("send-next-hops")) {
            _runSendNextHops();
            return;
        }
        if (key == keccak256("settle")) {
            _runSettle();
            return;
        }
        if (key == keccak256("claim")) {
            _runClaim();
            return;
        }
        if (key == keccak256("status")) {
            _logStatus();
            return;
        }

        revert("ManualParimutuelSmoke: unknown SMOKE_ACTION");
    }

    function _controller() internal view returns (LaneController) {
        return LaneController(_envAddress("LANE_CONTROLLER", 0xf7a6CAa15Fa51d30439e32E220A507F04611544a));
    }

    function _linkToken() internal view returns (IERC20) {
        return IERC20(_envAddress("LINK_TOKEN", ChainConfig.sepoliaConfig().linkToken));
    }

    function _executorForChain(ChainConfig.Network network) internal view returns (LaneExecutor) {
        if (network == ChainConfig.Network.Sepolia) {
            return LaneExecutor(payable(_envAddress("LANE_EXECUTOR_SEPOLIA", 0xbd8b72eB19Fea6e25597F40a63Ea1DeF3C600990)));
        }
        if (network == ChainConfig.Network.ArbitrumSepolia) {
            return LaneExecutor(payable(_envAddress("LANE_EXECUTOR_ARBITRUM_SEPOLIA", 0xa159214985Bbb3f7e7A0F986C723262914150ac7)));
        }
        return LaneExecutor(payable(_envAddress("LANE_EXECUTOR_BASE_SEPOLIA", 0xf2682e839FD4aC8bA60081710ce8689CCcc7e803)));
    }

    function _roundId(LaneController controller) internal view returns (uint256 roundId) {
        roundId = vm.envOr("ROUND_ID", uint256(0));
        if (roundId == 0) {
            roundId = controller.currentRoundId();
        }
        require(roundId > 0, "no round");
    }

    /// @dev Same paths as `cre/lane-checker-cre/round-scheduler/config.staging.json`.
    function _stagingLanePaths() internal pure returns (uint64[][] memory paths) {
        paths = new uint64[][](LANE_COUNT);
        paths[0] = new uint64[](3);
        paths[0][0] = ChainConfig.SEPOLIA_SELECTOR;
        paths[0][1] = ChainConfig.ARBITRUM_SEPOLIA_SELECTOR;
        paths[0][2] = ChainConfig.BASE_SEPOLIA_SELECTOR;
        paths[1] = new uint64[](3);
        paths[1][0] = ChainConfig.SEPOLIA_SELECTOR;
        paths[1][1] = ChainConfig.BASE_SEPOLIA_SELECTOR;
        paths[1][2] = ChainConfig.ARBITRUM_SEPOLIA_SELECTOR;
    }

    function _runSetup() internal {
        LaneController controller = _controller();
        _startDeployBroadcast();
        uint256 roundId = controller.createRound(_stagingLanePaths());
        vm.stopBroadcast();
        console2.log("Round created:", roundId);
        console2.log("Next: SMOKE_ACTION=bet (optional) then SMOKE_ACTION=start");
    }

    function _runBet() internal {
        LaneController controller = _controller();
        uint256 roundId = _roundId(controller);
        uint8 laneId = uint8(vm.envOr("BET_LANE", uint256(0)));
        uint256 amount = vm.envOr("BET_AMOUNT", uint256(0.2 ether));

        _startDeployBroadcast();
        IERC20 link = _linkToken();
        link.approve(address(controller), amount);
        controller.buyLaneTokens(roundId, laneId, amount);
        vm.stopBroadcast();

        console2.log("Bet placed round", roundId);
        console2.log("  lane", laneId);
        console2.log("  amount", amount);
    }

    function _runStart() internal {
        LaneController controller = _controller();
        uint256 roundId = _roundId(controller);

        _startDeployBroadcast();
        controller.startRace(roundId);
        vm.stopBroadcast();

        console2.log("Race started round", roundId);
    }

    function _runSendNextHops() internal {
        ChainConfig.Network network = ChainConfig.networkFromEnv(vm.envString("SMOKE_CHAIN"));
        LaneController controller = _controller();
        uint256 roundId = _roundId(controller);

        LaneController.RoundState state = controller.getRoundState(roundId);
        require(
            state == LaneController.RoundState.Racing || state == LaneController.RoundState.Finished,
            "round not active"
        );

        uint64 localSelector = ChainConfig.getNetworkConfig(network).chainSelector;
        LaneExecutor executor = _executorForChain(network);
        uint256 sent;

        _startDeployBroadcast();
        for (uint8 laneId = 0; laneId < LANE_COUNT; laneId++) {
            (uint64[] memory path, uint8 hopsCompleted, uint8 requiredHops,,, bool finished) =
                controller.getLane(roundId, laneId);
            if (finished || hopsCompleted >= requiredHops) {
                continue;
            }

            uint64 destSelector = path[hopsCompleted];
            uint64 senderSelector = hopsCompleted == 0
                ? ChainConfig.SEPOLIA_SELECTOR
                : path[hopsCompleted - 1];
            if (senderSelector != localSelector) {
                continue;
            }

            executor.sendHop(roundId, laneId, destSelector);
            sent++;
            console2.log("sendHop lane", laneId);
        }
        vm.stopBroadcast();

        console2.log("Hops sent count", sent);
    }

    function _runSettle() internal {
        LaneController controller = _controller();
        uint256 roundId = _roundId(controller);
        require(
            controller.getRoundState(roundId) == LaneController.RoundState.Finished,
            "round not finished"
        );

        _startDeployBroadcast();
        controller.distributePrizes(roundId);
        vm.stopBroadcast();

        console2.log("Prizes distributed round", roundId);
        console2.log("Winner lane", controller.getRoundWinner(roundId));
        console2.log("Runner-up lane", controller.getRoundRunnerUp(roundId));
    }

    function _runClaim() internal {
        LaneController controller = _controller();
        uint256 roundId = _roundId(controller);
        require(
            controller.getRoundState(roundId) == LaneController.RoundState.Settled,
            "round not settled"
        );

        _startDeployBroadcast();
        uint256 payout = controller.claimPrize(roundId);
        vm.stopBroadcast();

        console2.log("Claimed round", roundId);
        console2.log("  payout", payout);
    }

    function _logStatus() internal view {
        LaneController controller = _controller();
        uint256 roundId = _roundId(controller);

        console2.log("=== Parimutuel status ===");
        console2.log("Controller:", address(controller));
        console2.log("Round:", roundId);
        console2.log("State:", uint256(controller.getRoundState(roundId)));
        console2.log("Prize pool:", controller.getTotalPrizePool(roundId));
        console2.log("Winner lane:", controller.getRoundWinner(roundId));
        console2.log("Runner-up lane:", controller.getRoundRunnerUp(roundId));

        for (uint8 laneId = 0; laneId < LANE_COUNT; laneId++) {
            (uint64[] memory path, uint8 hopsCompleted, uint8 requiredHops,,, bool finished) =
                controller.getLane(roundId, laneId);
            console2.log("--- Lane", laneId, "---");
            console2.log("  hops completed", hopsCompleted);
            console2.log("  required", requiredHops);
            console2.log("  finished", finished);
            console2.log("  path[0]", path[0]);
            console2.log("  path[1]", path[1]);
            console2.log("  path[2]", path[2]);
            if (!finished && hopsCompleted < requiredHops) {
                uint64 dest = path[hopsCompleted];
                uint64 sender = hopsCompleted == 0 ? ChainConfig.SEPOLIA_SELECTOR : path[hopsCompleted - 1];
                console2.log("  next dest selector", dest);
                console2.log("  send from selector", sender);
            }
        }
    }

    function _envAddress(string memory name, address fallbackAddr) internal view returns (address) {
        try vm.envAddress(name) returns (address value) {
            return value;
        } catch {
            return fallbackAddr;
        }
    }
}
