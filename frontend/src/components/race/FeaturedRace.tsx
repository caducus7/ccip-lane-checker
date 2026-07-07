"use client";

import { LaneRaceViz } from "@/components/race/LaneRaceViz";
import { demoLaneStates } from "@/lib/lane-data";
import { useDeploymentStatus } from "@/hooks/useDeploymentStatus";
import { useRoundCounter } from "@/hooks/useLaneController";
import { DeploymentBanner } from "@/components/ui/EmptyState";
import { Skeleton } from "@/components/ui/Skeleton";

export function FeaturedRace() {
  const { controllerDeployed } = useDeploymentStatus();
  const { data: currentRoundId, isLoading } = useRoundCounter();

  if (!controllerDeployed) {
    return (
      <div className="space-y-4">
        <DeploymentBanner contractName="LaneController" />
        <LaneRaceViz
          lanes={demoLaneStates()}
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

  return <LaneRaceViz lanes={demoLaneStates()} title={title} />;
}
