"use client";

import { LaneRaceViz } from "@/components/race/LaneRaceViz";
import { demoLaneStates } from "@/lib/lane-data";
import { useDeploymentStatus } from "@/hooks/useDeploymentStatus";
import { useRoundCounter } from "@/hooks/useLaneController";
import { useLiveLanes } from "@/hooks/useLiveLanes";
import { PARIMUTUEL_LANE_COUNT } from "@/lib/race-paths";
import { DeploymentBanner } from "@/components/ui/EmptyState";
import { Skeleton } from "@/components/ui/Skeleton";

export function FeaturedRace() {
  const { controllerDeployed } = useDeploymentStatus();
  const { data: currentRoundId, isLoading } = useRoundCounter();
  const { lanes, isLive } = useLiveLanes(
    currentRoundId && currentRoundId > 0n ? currentRoundId : undefined,
  );

  if (!controllerDeployed) {
    return (
      <div className="space-y-4">
        <DeploymentBanner contractName="LaneController" />
        <LaneRaceViz
          lanes={demoLaneStates().slice(0, PARIMUTUEL_LANE_COUNT)}
          title="Featured Race — demo"
        />
      </div>
    );
  }

  if (isLoading) {
    return <Skeleton className="h-64 w-full" />;
  }

  const title =
    currentRoundId && currentRoundId > 0n
      ? `Featured Race — Round #${currentRoundId.toString()}`
      : "Featured Race";

  return (
    <LaneRaceViz
      lanes={lanes}
      title={isLive ? title : `${title} (demo)`}
    />
  );
}
