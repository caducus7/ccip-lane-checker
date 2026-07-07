"use client";

import { useState } from "react";
import { formatEther } from "viem";
import {
  RoundStateLabel,
  useLaneControllerActions,
  useLanePool,
  useRoundState,
  useTotalPrizePool,
} from "@/hooks/useLaneController";
import { LaneRaceViz } from "@/components/race/LaneRaceViz";
import { demoLaneStates } from "@/lib/lane-data";
import { ccipExplorerHome } from "@/lib/ccip";

interface BettingPanelProps {
  roundId: bigint;
}

const LANE_LABELS = ["SEP→ARB→SEP", "ARB→SEP→ARB", "SEP→BASE→SEP"];

export function BettingPanel({ roundId }: BettingPanelProps) {
  const [selectedLane, setSelectedLane] = useState(0);
  const [betAmount, setBetAmount] = useState("0.05");

  const { data: roundState } = useRoundState(roundId);
  const { data: totalPrizePool } = useTotalPrizePool(roundId);
  const { data: lane0 } = useLanePool(roundId, 0);
  const { data: lane1 } = useLanePool(roundId, 1);
  const { data: lane2 } = useLanePool(roundId, 2);
  const {
    approveBettingToken,
    buyLaneTokens,
    claimPrize,
    isPending,
    isConfirming,
    isDeployed,
    hash,
  } = useLaneControllerActions();

  const laneCount = 3;
  const status =
    roundState !== undefined
      ? RoundStateLabel[Number(roundState)] ?? "betting"
      : isDeployed
        ? "betting"
        : "racing";
  const lanePools = [lane0, lane1, lane2];
  const totalPool =
    totalPrizePool ?? lanePools.reduce<bigint>((sum, p) => sum + (p ?? 0n), 0n);
  const demoLanes = demoLaneStates();

  const vizLanes = lanePools.some((p) => p !== undefined && p > 0n)
    ? lanePools.map((pool, i) => ({
        id: i,
        label: LANE_LABELS[i] ?? `Lane ${i}`,
        color: demoLanes[i]?.color ?? "#00f5d4",
        progress: demoLanes[i]?.progress ?? 0,
        hopsCompleted: demoLanes[i]?.hopsCompleted ?? 0,
        maxHops: 5,
        latencySec: demoLanes[i]?.latencySec ?? 0,
        finished: demoLanes[i]?.finished ?? false,
      }))
    : demoLanes;

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-4">
        <div>
          <span className="font-mono text-[10px] uppercase tracking-[0.3em] text-neon-amber">
            Parimutuel
          </span>
          <h1 className="font-display text-3xl sm:text-4xl tracking-wider uppercase mt-1">
            Round <span className="text-neon-cyan">#{roundId.toString()}</span>
          </h1>
        </div>
        <div className="flex items-center gap-3">
          <StatusPill status={status} />
          <a
            href={ccipExplorerHome()}
            target="_blank"
            rel="noopener noreferrer"
            className="font-mono text-[10px] uppercase tracking-widest text-neon-cyan/60 hover:text-neon-cyan"
          >
            CCIP Explorer
          </a>
        </div>
      </div>

      {!isDeployed && (
        <div className="border border-neon-amber/40 bg-neon-amber/5 px-4 py-3 font-mono text-xs text-neon-amber">
          LaneController not deployed. Showing demo race visualization.
        </div>
      )}

      <LaneRaceViz lanes={vizLanes} title="Multi-Lane Race" />

      <div className="grid gap-6 lg:grid-cols-2">
        <div className="border border-grid bg-asphalt-50 p-5 space-y-4">
          <h2 className="font-display tracking-widest uppercase">
            Prize <span className="text-neon-amber">Pool</span>
          </h2>
          <p className="font-display text-4xl text-white">
            {totalPool > 0n
              ? `${formatEther(totalPool)} LINK`
              : "2.4 LINK"}
          </p>
          <p className="font-mono text-xs text-white/40">
            70% winner · 15% 2nd · 10% 3rd · 5% protocol
          </p>

          <ul className="space-y-2 pt-2 border-t border-grid">
            {vizLanes.map((lane, i) => (
              <li
                key={lane.id}
                className="flex justify-between font-mono text-xs"
              >
                <span style={{ color: lane.color }}>{lane.label}</span>
                <span className="text-white/50">
                  {lanePools[i] !== undefined && lanePools[i]! > 0n
                    ? `${formatEther(lanePools[i]!)} LINK`
                    : "—"}
                </span>
              </li>
            ))}
          </ul>
        </div>

        <div className="border border-grid bg-asphalt-50 p-5 space-y-4">
          <h2 className="font-display tracking-widest uppercase">
            Place <span className="text-neon-cyan">Bet</span>
          </h2>

          <div className="grid grid-cols-3 gap-2">
            {Array.from({ length: laneCount }).map((_, i) => (
              <button
                key={i}
                type="button"
                onClick={() => setSelectedLane(i)}
                className={`py-3 font-mono text-xs uppercase tracking-wider border transition-colors ${
                  selectedLane === i
                    ? "border-neon-cyan bg-neon-cyan/10 text-neon-cyan"
                    : "border-grid text-white/50 hover:border-white/30"
                }`}
              >
                Lane {i}
              </button>
            ))}
          </div>

          <label className="block">
            <span className="font-mono text-[10px] uppercase tracking-widest text-white/40">
              Amount (LINK)
            </span>
            <input
              type="text"
              value={betAmount}
              onChange={(e) => setBetAmount(e.target.value)}
              disabled={status !== "betting"}
              className="mt-1 w-full border border-grid bg-asphalt px-3 py-2 font-mono text-sm text-white focus:border-neon-cyan outline-none disabled:opacity-40"
            />
          </label>

          <button
            type="button"
            disabled={!isDeployed || isPending || isConfirming}
            onClick={() => approveBettingToken(betAmount)}
            className="w-full py-2 font-mono text-xs uppercase tracking-[0.2em] border border-grid text-white/60 hover:border-neon-cyan/50 disabled:opacity-40"
          >
            Approve LINK
          </button>

          <button
            type="button"
            disabled={
              !isDeployed || status !== "betting" || isPending || isConfirming
            }
            onClick={() => buyLaneTokens(roundId, selectedLane, betAmount)}
            className="w-full py-3 font-mono text-sm uppercase tracking-[0.2em] bg-neon-amber text-asphalt font-bold hover:shadow-[0_0_24px_rgba(255,183,3,0.35)] transition-shadow disabled:opacity-40"
          >
            {status !== "betting"
              ? "Betting Closed"
              : isPending || isConfirming
                ? "Confirming…"
                : `Bet on Lane ${selectedLane}`}
          </button>

          {status === "settled" && (
            <button
              type="button"
              disabled={!isDeployed || isPending || isConfirming}
              onClick={() => claimPrize(roundId)}
              className="w-full py-2 font-mono text-xs uppercase tracking-[0.2em] border border-neon-cyan text-neon-cyan hover:bg-neon-cyan/10 disabled:opacity-40"
            >
              Claim Prize
            </button>
          )}

          {hash && (
            <p className="font-mono text-[10px] text-white/40 break-all">
              Tx: {hash}
            </p>
          )}
        </div>
      </div>
    </div>
  );
}

function StatusPill({ status }: { status: string }) {
  const colors: Record<string, string> = {
    betting: "bg-neon-amber/20 text-neon-amber border-neon-amber/40",
    racing: "bg-neon-red/20 text-neon-red border-neon-red/40",
    settled: "bg-white/10 text-white/50 border-white/20",
  };

  return (
    <span
      className={`px-3 py-1 font-mono text-[10px] uppercase tracking-widest border ${colors[status] ?? ""}`}
    >
      {status}
    </span>
  );
}
