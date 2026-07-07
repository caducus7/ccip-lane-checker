export interface LaneState {
  id: number;
  label: string;
  color: string;
  progress: number;
  hopsCompleted: number;
  maxHops: number;
  latencySec: number;
  finished?: boolean;
}

export function demoLaneStates(): LaneState[] {
  return [
    {
      id: 0,
      label: "SEP→ARB",
      color: "#00f5d4",
      progress: 72,
      hopsCompleted: 3,
      maxHops: 5,
      latencySec: 128,
    },
    {
      id: 1,
      label: "ARB→SEP",
      color: "#ffb703",
      progress: 58,
      hopsCompleted: 2,
      maxHops: 5,
      latencySec: 94,
    },
    {
      id: 2,
      label: "SEP→BASE",
      color: "#ff3366",
      progress: 45,
      hopsCompleted: 2,
      maxHops: 5,
      latencySec: 112,
    },
  ];
}

export interface LaneBenchmark {
  id: string;
  source: string;
  destination: string;
  sourceSelector: string;
  destSelector: string;
  p50LatencySec: number;
  p95LatencySec: number;
  feeUsd: number;
  successRate: number;
  health: "excellent" | "good" | "degraded" | "down";
  lastUpdated: string;
}

/** Static placeholder — replaced by CRE lane-benchmark workflow cache */
export const LANE_BENCHMARKS: LaneBenchmark[] = [
  {
    id: "sep-arb",
    source: "Ethereum Sepolia",
    destination: "Arbitrum Sepolia",
    sourceSelector: "16015286601757825753",
    destSelector: "3478487238524512106",
    p50LatencySec: 42,
    p95LatencySec: 89,
    feeUsd: 0.12,
    successRate: 99.2,
    health: "good",
    lastUpdated: "2026-07-07T10:00:00Z",
  },
  {
    id: "arb-sep",
    source: "Arbitrum Sepolia",
    destination: "Ethereum Sepolia",
    sourceSelector: "3478487238524512106",
    destSelector: "16015286601757825753",
    p50LatencySec: 38,
    p95LatencySec: 76,
    feeUsd: 0.09,
    successRate: 99.5,
    health: "excellent",
    lastUpdated: "2026-07-07T10:00:00Z",
  },
  {
    id: "sep-base",
    source: "Ethereum Sepolia",
    destination: "Base Sepolia",
    sourceSelector: "16015286601757825753",
    destSelector: "10344971235874465080",
    p50LatencySec: 55,
    p95LatencySec: 112,
    feeUsd: 0.14,
    successRate: 98.8,
    health: "good",
    lastUpdated: "2026-07-07T10:00:00Z",
  },
  {
    id: "base-sep",
    source: "Base Sepolia",
    destination: "Ethereum Sepolia",
    sourceSelector: "10344971235874465080",
    destSelector: "16015286601757825753",
    p50LatencySec: 48,
    p95LatencySec: 95,
    feeUsd: 0.11,
    successRate: 99.1,
    health: "good",
    lastUpdated: "2026-07-07T10:00:00Z",
  },
];

export interface LeaderboardEntry {
  rank: number;
  player: string;
  mode: "solo" | "parimutuel";
  totalLatencySec: number;
  hops: number;
  roundId?: number;
  timestamp: string;
}

export const MOCK_LEADERBOARD: LeaderboardEntry[] = [
  {
    rank: 1,
    player: "0x71C7…4F2a",
    mode: "solo",
    totalLatencySec: 186,
    hops: 5,
    timestamp: "2026-07-06T18:22:00Z",
  },
  {
    rank: 2,
    player: "0x9a3B…8c1D",
    mode: "parimutuel",
    totalLatencySec: 201,
    hops: 4,
    roundId: 3,
    timestamp: "2026-07-06T14:10:00Z",
  },
  {
    rank: 3,
    player: "0xE4f2…91Ab",
    mode: "solo",
    totalLatencySec: 224,
    hops: 5,
    timestamp: "2026-07-05T22:45:00Z",
  },
  {
    rank: 4,
    player: "0x2d8C…77e0",
    mode: "parimutuel",
    totalLatencySec: 238,
    hops: 4,
    roundId: 2,
    timestamp: "2026-07-05T11:30:00Z",
  },
];

export interface ActiveRound {
  roundId: number;
  status: "betting" | "racing" | "settled";
  totalPool: string;
  laneCount: number;
  bettingEndsAt?: string;
}

export const MOCK_ACTIVE_ROUNDS: ActiveRound[] = [
  {
    roundId: 4,
    status: "betting",
    totalPool: "2.4 ETH",
    laneCount: 3,
    bettingEndsAt: "2026-07-07T12:00:00Z",
  },
  {
    roundId: 3,
    status: "racing",
    totalPool: "1.8 ETH",
    laneCount: 3,
  },
];

export function healthColor(health: LaneBenchmark["health"]): string {
  switch (health) {
    case "excellent":
      return "text-neon-cyan";
    case "good":
      return "text-neon-lime";
    case "degraded":
      return "text-neon-amber";
    case "down":
      return "text-neon-red";
  }
}
