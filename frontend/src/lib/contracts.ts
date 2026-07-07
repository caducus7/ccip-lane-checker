import type { Address } from "viem";
import { parseAbi } from "viem";
import testnetDeployments from "../../../contracts/deployments/testnet.json";

export type ChainDeploymentKey =
  | "ethereum-sepolia"
  | "arbitrum-sepolia"
  | "base-sepolia";

export interface ChainDeployment {
  chainId: number;
  ccipChainSelector: string;
  laneToken: Address;
  laneController: Address;
  laneExecutor: Address;
  underlyingToken: Address;
}

const ZERO = "0x0000000000000000000000000000000000000000" as Address;

type RawDeployment = typeof testnetDeployments;

const ENV_BY_CHAIN: Record<
  ChainDeploymentKey,
  {
    laneToken: string | undefined;
    laneController: string | undefined;
    laneExecutor: string | undefined;
    linkToken: string | undefined;
  }
> = {
  "ethereum-sepolia": {
    laneToken: process.env.NEXT_PUBLIC_SEPOLIA_LANE_TOKEN,
    laneController: process.env.NEXT_PUBLIC_SEPOLIA_LANE_CONTROLLER,
    laneExecutor: process.env.NEXT_PUBLIC_SEPOLIA_LANE_EXECUTOR,
    linkToken: process.env.NEXT_PUBLIC_SEPOLIA_LINK,
  },
  "arbitrum-sepolia": {
    laneToken: process.env.NEXT_PUBLIC_ARBITRUM_SEPOLIA_LANE_TOKEN,
    laneController: process.env.NEXT_PUBLIC_ARBITRUM_SEPOLIA_LANE_CONTROLLER,
    laneExecutor: process.env.NEXT_PUBLIC_ARBITRUM_SEPOLIA_LANE_EXECUTOR,
    linkToken: process.env.NEXT_PUBLIC_ARBITRUM_SEPOLIA_LINK,
  },
  "base-sepolia": {
    laneToken: process.env.NEXT_PUBLIC_BASE_SEPOLIA_LANE_TOKEN,
    laneController: process.env.NEXT_PUBLIC_BASE_SEPOLIA_LANE_CONTROLLER,
    laneExecutor: process.env.NEXT_PUBLIC_BASE_SEPOLIA_LANE_EXECUTOR,
    linkToken: process.env.NEXT_PUBLIC_BASE_SEPOLIA_LINK,
  },
};

function resolveAddress(
  fromDeployment: string | null | undefined,
  fromEnv: string | undefined
): Address {
  const candidate = fromDeployment ?? fromEnv;
  if (!candidate || !/^0x[a-fA-F0-9]{40}$/.test(candidate)) {
    return ZERO;
  }
  return candidate as Address;
}

function mapChain(key: ChainDeploymentKey): ChainDeployment {
  const chain = raw.chains[key];
  const env = ENV_BY_CHAIN[key];
  return {
    chainId: chain.chainId,
    ccipChainSelector: chain.chainSelector,
    laneToken: resolveAddress(chain.contracts.LaneToken, env.laneToken),
    laneController: resolveAddress(
      chain.contracts.LaneController,
      env.laneController
    ),
    laneExecutor: resolveAddress(chain.contracts.LaneExecutor, env.laneExecutor),
    underlyingToken: resolveAddress(chain.infra.linkToken, env.linkToken),
  };
}

const raw = testnetDeployments as RawDeployment;

export const deployments = {
  version: raw.version,
  updatedAt: raw.updatedAt ?? "",
  chains: {
    "ethereum-sepolia": mapChain("ethereum-sepolia"),
    "arbitrum-sepolia": mapChain("arbitrum-sepolia"),
    "base-sepolia": mapChain("base-sepolia"),
  } satisfies Record<ChainDeploymentKey, ChainDeployment>,
  vrf: Object.fromEntries(
    (Object.keys(raw.chains) as ChainDeploymentKey[]).map((key) => [
      key,
      {
        coordinator: raw.chains[key].infra.vrfCoordinator as Address,
        subscriptionId: raw.chains[key].infra.vrfSubscriptionId ?? "0",
      },
    ])
  ),
  ccipRouter: Object.fromEntries(
    (Object.keys(raw.chains) as ChainDeploymentKey[]).map((key) => [
      key,
      raw.chains[key].infra.ccipRouter as Address,
    ])
  ) as Record<ChainDeploymentKey, Address>,
};

export function getDeploymentByChainId(
  chainId: number
): ChainDeployment | undefined {
  return Object.values(deployments.chains).find((c) => c.chainId === chainId);
}

export function getLaneTokenAddress(chainId: number): Address | undefined {
  return getDeploymentByChainId(chainId)?.laneToken;
}

export function getLaneControllerAddress(chainId: number): Address | undefined {
  return getDeploymentByChainId(chainId)?.laneController;
}

export function isDeployed(address: Address | undefined): boolean {
  return !!address && address !== ZERO;
}

export function isChainDeployed(chainId: number): boolean {
  const deployment = getDeploymentByChainId(chainId);
  if (!deployment) return false;
  return (
    isDeployed(deployment.laneController) || isDeployed(deployment.laneToken)
  );
}

export function hasAnyDeployment(): boolean {
  return Object.values(deployments.chains).some(
    (chain) =>
      isDeployed(chain.laneController) || isDeployed(chain.laneToken)
  );
}

/** Minimal ABI for LaneToken solo mode */
export const laneTokenAbi = parseAbi([
  "function deposit(uint256 amount) external",
  "function withdraw(uint256 amount) external",
  "function startGame(uint64 destinationChainSelector, uint256 amount, uint8 maxHops) external returns (bytes32 messageId)",
  "function getGameRound(uint256 gameId) external view returns (address player, uint256 amount, uint8 maxHops, uint8 hopsCompleted, uint256 totalLatency, uint256 lastSendTime, bool isActive)",
  "function s_gameCounter() external view returns (uint256)",
  "function s_balances(address user) external view returns (uint256)",
  "event GameRoundStarted(uint256 indexed gameId, address indexed initiator, uint256 amount, uint8 maxHops)",
  "event HopCompleted(uint256 indexed gameId, uint64 fromChain, uint256 latency, uint8 hopCount)",
  "event GameFinished(uint256 indexed gameId, uint256 totalLatency, uint8 totalHops)",
  "event BridgeStarted(bytes32 indexed messageId, uint64 destChainSelector, uint256 amount)",
]);

/**
 * LaneController ABI — aligned with cre/lane-checker-cre/shared/lane-controller-abi.ts
 * plus frontend read helpers (buyLaneTokens, getLanePool, getTotalPrizePool, getRoundRunnerUp).
 */
export const laneControllerAbi = parseAbi([
  "function createRound(uint64[][] lanePaths) external returns (uint256 roundId)",
  "function buyLaneTokens(uint256 roundId, uint8 laneId, uint256 amount) external",
  "function startRace(uint256 roundId) external",
  "function declareWinner(uint256 roundId, uint8 laneId) external",
  "function distributePrizes(uint256 roundId) external",
  "function claimPrize(uint256 roundId) external returns (uint256 amount)",
  "function sweepUnclaimed(uint256 roundId) external",
  "function getRoundWinner(uint256 roundId) external view returns (uint8 winnerLaneId)",
  "function getRoundRunnerUp(uint256 roundId) external view returns (uint8 runnerUpLaneId)",
  "function getRoundState(uint256 roundId) external view returns (uint8 state)",
  "function getLane(uint256 roundId, uint8 laneId) external view returns (uint64[] chainPath, uint8 hopsCompleted, uint8 requiredHops, uint256 totalLatency, uint256 finishTime, bool finished)",
  "function getLanePool(uint256 roundId, uint8 laneId) external view returns (uint256)",
  "function getTotalPrizePool(uint256 roundId) external view returns (uint256)",
  "function currentRoundId() external view returns (uint256)",
  "event RoundCreated(uint256 indexed roundId, uint8 laneCount)",
  "event BetPlaced(uint256 indexed roundId, uint8 indexed laneId, address indexed bettor, uint256 amount)",
  "event RaceStarted(uint256 indexed roundId)",
  "event HopCompleted(uint256 indexed roundId, uint8 indexed laneId, uint64 chainSelector, uint256 latency, uint8 hopIndex)",
  "event LaneFinished(uint256 indexed roundId, uint8 indexed laneId, uint256 finishTime)",
  "event WinnerDeclared(uint256 indexed roundId, uint8 indexed laneId, uint256 finishTime)",
  "event PrizesDistributed(uint256 indexed roundId, uint8 winnerLaneId, uint256 winnerPayout)",
  "event PrizeClaimed(uint256 indexed roundId, address indexed bettor, uint256 amount)",
]);

/** RoundState enum values from LaneController.sol */
export const RoundState = {
  Betting: 0,
  Racing: 1,
  Finished: 2,
  Settled: 3,
} as const;

export const erc20Abi = parseAbi([
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function allowance(address owner, address spender) external view returns (uint256)",
  "function balanceOf(address account) external view returns (uint256)",
  "function decimals() external view returns (uint8)",
]);

export const ZERO_ADDRESS = ZERO;
