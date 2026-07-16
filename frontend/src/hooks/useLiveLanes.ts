"use client";

import { useMemo } from "react";
import {
  useHomeLane,
} from "@/hooks/useHomeLaneController";
import {
  laneToVizState,
  PARIMUTUEL_LANE_COUNT,
} from "@/lib/race-paths";
import { demoLaneStates, type LaneState } from "@/lib/lane-data";

export function useLiveLanes(roundId: bigint | undefined): {
  lanes: LaneState[];
  isLive: boolean;
} {
  const lane0 = useHomeLane(roundId, 0);
  const lane1 = useHomeLane(roundId, 1);

  return useMemo(() => {
    const reads = [lane0, lane1];
    const hasData = reads.some((r) => r.data !== undefined);

    if (!hasData || roundId === undefined) {
      return { lanes: demoLaneStates().slice(0, PARIMUTUEL_LANE_COUNT), isLive: false };
    }

    const lanes: LaneState[] = [];
    for (let i = 0; i < PARIMUTUEL_LANE_COUNT; i++) {
      const data = reads[i]?.data;
      if (!data) continue;
      const [chainPath, hopsCompleted, requiredHops, totalLatency, , finished] =
        data;
      lanes.push(
        laneToVizState(
          i,
          chainPath,
          hopsCompleted,
          requiredHops,
          totalLatency,
          finished,
        ),
      );
    }

    return { lanes, isLive: lanes.length > 0 };
  }, [lane0.data, lane1.data, roundId]);
}
