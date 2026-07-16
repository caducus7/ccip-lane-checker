import type { LaneState } from "@/lib/lane-data";
import {
  CCIP_CHAIN_SELECTORS,
  CHAIN_SHORT,
  type SupportedChainId,
  selectorToChainId,
} from "@/lib/chains";
import { sepolia } from "viem/chains";

/** Matches round-scheduler + ManualParimutuelSmoke staging paths. */
export const STAGING_LANE_PATHS: readonly (readonly bigint[])[] = [
  [
    16015286601757825753n,
    3478487238524512106n,
    10344971235874465080n,
  ],
  [
    16015286601757825753n,
    10344971235874465080n,
    3478487238524512106n,
  ],
] as const;

export const PARIMUTUEL_LANE_COUNT = STAGING_LANE_PATHS.length;

const LANE_COLORS = ["#00f5d4", "#ffb703", "#ff3366", "#c8f135"];

export function formatPathLabel(chainPath: readonly bigint[]): string {
  return chainPath
    .map((selector) => {
      const chainId = selectorToChainId(selector);
      return chainId ? CHAIN_SHORT[chainId] : selector.toString().slice(0, 6);
    })
    .join("→");
}

export function laneToVizState(
  laneId: number,
  chainPath: readonly bigint[],
  hopsCompleted: number,
  requiredHops: number,
  totalLatency: bigint,
  finished: boolean,
): LaneState {
  const progress =
    requiredHops > 0 ? Math.round((hopsCompleted / requiredHops) * 100) : 0;

  return {
    id: laneId,
    label: formatPathLabel(chainPath),
    color: LANE_COLORS[laneId % LANE_COLORS.length],
    progress: finished ? 100 : progress,
    hopsCompleted,
    maxHops: requiredHops,
    latencySec: Number(totalLatency),
    finished,
  };
}

/** Which chain's executor should send the next hop for this lane. */
export function hopSenderChainId(
  chainPath: readonly bigint[],
  hopsCompleted: number,
): SupportedChainId | null {
  if (hopsCompleted >= chainPath.length) return null;
  const senderSelector =
    hopsCompleted === 0
      ? CCIP_CHAIN_SELECTORS[sepolia.id]
      : chainPath[hopsCompleted - 1];
  return selectorToChainId(senderSelector);
}

export function nextHopDestSelector(
  chainPath: readonly bigint[],
  hopsCompleted: number,
): bigint | null {
  if (hopsCompleted >= chainPath.length) return null;
  return chainPath[hopsCompleted];
}
