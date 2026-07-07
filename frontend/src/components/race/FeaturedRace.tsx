"use client";

import { LaneRaceViz } from "@/components/race/LaneRaceViz";
import { demoLaneStates } from "@/lib/lane-data";

export function FeaturedRace() {
  return (
    <LaneRaceViz lanes={demoLaneStates()} title="Featured Race — Round #3" />
  );
}
