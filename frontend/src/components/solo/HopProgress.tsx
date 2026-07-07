"use client";

import { formatEther } from "viem";
import { useGameRound } from "@/hooks/useLaneToken";
import { ccipExplorerMessageUrl } from "@/lib/ccip";
import { LaneRaceViz } from "@/components/race/LaneRaceViz";

interface HopProgressProps {
  gameId: bigint | undefined;
}

export function HopProgress({ gameId }: HopProgressProps) {
  const { data: round, isLoading, isError } = useGameRound(gameId);

  if (!gameId) {
    return (
      <div className="border border-grid bg-asphalt-50 p-6 flex items-center justify-center min-h-[280px]">
        <p className="font-mono text-sm text-white/40 text-center">
          Start a game or connect wallet to track hop progress.
        </p>
      </div>
    );
  }

  if (isLoading) {
    return (
      <div className="border border-grid bg-asphalt-50 p-6 animate-pulse min-h-[280px]" />
    );
  }

  if (isError || !round) {
    return (
      <div className="border border-grid bg-asphalt-50 p-6">
        <p className="font-mono text-sm text-neon-amber">
          Game #{gameId.toString()} — awaiting on-chain data
          {isError ? " (contract not deployed)" : ""}
        </p>
        <DemoProgress gameId={gameId} />
      </div>
    );
  }

  const [
    ,
    amount,
    maxHops,
    hopsCompleted,
    totalLatency,
    ,
    isActive,
  ] = round;

  const progress = maxHops > 0 ? (hopsCompleted / maxHops) * 100 : 0;

  return (
    <div className="space-y-4">
      <div className="border border-grid bg-asphalt-50 p-5">
        <div className="flex items-center justify-between mb-4">
          <h3 className="font-display tracking-widest uppercase">
            Game <span className="text-neon-cyan">#{gameId.toString()}</span>
          </h3>
          <span
            className={`font-mono text-[10px] uppercase tracking-widest px-2 py-1 border ${
              isActive
                ? "border-neon-red text-neon-red"
                : "border-neon-lime text-neon-lime"
            }`}
          >
            {isActive ? "Racing" : "Finished"}
          </span>
        </div>

        <dl className="grid grid-cols-2 gap-3 font-mono text-xs">
          <div>
            <dt className="text-white/40">Stake</dt>
            <dd className="text-neon-cyan">{formatEther(amount)} ETH</dd>
          </div>
          <div>
            <dt className="text-white/40">Latency</dt>
            <dd>{totalLatency.toString()}s</dd>
          </div>
          <div>
            <dt className="text-white/40">Hops</dt>
            <dd>
              {hopsCompleted}/{maxHops}
            </dd>
          </div>
          <div>
            <dt className="text-white/40">Explorer</dt>
            <dd>
              <a
                href={ccipExplorerMessageUrl("0x" + "0".repeat(64))}
                target="_blank"
                rel="noopener noreferrer"
                className="text-neon-cyan/70 hover:text-neon-cyan"
              >
                CCIP →
              </a>
            </dd>
          </div>
        </dl>
      </div>

      <LaneRaceViz
        title="Solo Progress"
        compact
        lanes={[
          {
            id: 0,
            label: "Your lane",
            color: "#00f5d4",
            progress,
            hopsCompleted,
            maxHops,
            latencySec: Number(totalLatency),
            finished: !isActive,
          },
        ]}
      />
    </div>
  );
}

function DemoProgress({ gameId }: { gameId: bigint }) {
  return (
    <div className="mt-4">
      <LaneRaceViz
        title={`Game #${gameId.toString()} (demo)`}
        compact
        lanes={[
          {
            id: 0,
            label: "CCIP hops",
            color: "#00f5d4",
            progress: 40,
            hopsCompleted: 2,
            maxHops: 5,
            latencySec: 86,
          },
        ]}
      />
    </div>
  );
}
