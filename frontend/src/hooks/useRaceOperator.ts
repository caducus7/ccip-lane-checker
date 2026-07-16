"use client";

import { useCallback, useMemo, useState } from "react";
import {
  useAccount,
  useSwitchChain,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { sepolia } from "viem/chains";
import {
  getHomeLaneController,
  getLaneExecutorAddress,
  isDeployed,
  laneControllerAbi,
  laneExecutorAbi,
  RoundState,
} from "@/lib/contracts";
import {
  hopSenderChainId,
  nextHopDestSelector,
  PARIMUTUEL_LANE_COUNT,
  STAGING_LANE_PATHS,
} from "@/lib/race-paths";
import {
  CHAIN_LABELS,
  type SupportedChainId,
} from "@/lib/chains";
import { useControllerOwner, useHomeLane } from "@/hooks/useHomeLaneController";

export type OperatorAction =
  | "createRound"
  | "startRace"
  | "distributePrizes"
  | "sendHop"
  | null;

export function useIsControllerOwner() {
  const { address } = useAccount();
  const { data: owner } = useControllerOwner();
  return !!address && !!owner && address.toLowerCase() === owner.toLowerCase();
}

export function useRaceOperator(roundId: bigint | undefined) {
  const { chainId } = useAccount();
  const isOwner = useIsControllerOwner();
  const { switchChainAsync } = useSwitchChain();
  const [pendingAction, setPendingAction] = useState<OperatorAction>(null);

  const controller = getHomeLaneController();
  const homeChainId = sepolia.id;

  const lane0 = useHomeLane(roundId, 0);
  const lane1 = useHomeLane(roundId, 1);

  const {
    writeContract,
    data: hash,
    isPending,
    error,
    reset: resetWrite,
  } = useWriteContract();

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  const pendingHops = useMemo(() => {
    if (roundId === undefined) return [];

    const lanes = [lane0.data, lane1.data];
    const hints: Array<{
      laneId: number;
      senderChainId: SupportedChainId;
      destSelector: bigint;
    }> = [];

    for (let laneId = 0; laneId < PARIMUTUEL_LANE_COUNT; laneId++) {
      const lane = lanes[laneId];
      if (!lane) continue;
      const [chainPath, hopsCompleted, requiredHops, , , finished] = lane;
      if (finished || hopsCompleted >= requiredHops) continue;

      const senderChainId = hopSenderChainId(chainPath, hopsCompleted);
      const dest = nextHopDestSelector(chainPath, hopsCompleted);
      if (senderChainId === null || dest === null) continue;

      hints.push({ laneId, senderChainId, destSelector: dest });
    }

    return hints;
  }, [lane0.data, lane1.data, roundId]);

  const hopsOnCurrentChain = pendingHops.filter(
    (h) => h.senderChainId === chainId,
  );

  const createRound = useCallback(() => {
    if (!controller || !isDeployed(controller) || !isOwner) return;
    setPendingAction("createRound");
    writeContract({
      chainId: homeChainId,
      address: controller,
      abi: laneControllerAbi,
      functionName: "createRound",
      args: [STAGING_LANE_PATHS.map((path) => [...path])],
    });
  }, [controller, homeChainId, isOwner, writeContract]);

  const startRace = useCallback(() => {
    if (!controller || !isDeployed(controller) || !isOwner || roundId === undefined) {
      return;
    }
    setPendingAction("startRace");
    writeContract({
      chainId: homeChainId,
      address: controller,
      abi: laneControllerAbi,
      functionName: "startRace",
      args: [roundId],
    });
  }, [controller, homeChainId, isOwner, roundId, writeContract]);

  const distributePrizes = useCallback(() => {
    if (!controller || !isDeployed(controller) || !isOwner || roundId === undefined) {
      return;
    }
    setPendingAction("distributePrizes");
    writeContract({
      chainId: homeChainId,
      address: controller,
      abi: laneControllerAbi,
      functionName: "distributePrizes",
      args: [roundId],
    });
  }, [controller, homeChainId, isOwner, roundId, writeContract]);

  const sendHopsOnCurrentChain = useCallback(() => {
    if (!isOwner || roundId === undefined || chainId === undefined) return;

    const executor = getLaneExecutorAddress(chainId);
    if (!executor || !isDeployed(executor)) return;

    for (const hop of hopsOnCurrentChain) {
      setPendingAction("sendHop");
      writeContract({
        chainId,
        address: executor,
        abi: laneExecutorAbi,
        functionName: "sendHop",
        args: [roundId, hop.laneId, hop.destSelector],
      });
      break;
    }
  }, [chainId, hopsOnCurrentChain, isOwner, roundId, writeContract]);

  const switchToChain = useCallback(
    async (targetChainId: SupportedChainId) => {
      await switchChainAsync({ chainId: targetChainId });
    },
    [switchChainAsync],
  );

  return {
    isOwner,
    createRound,
    startRace,
    distributePrizes,
    sendHopsOnCurrentChain,
    switchToChain,
    pendingHops,
    hopsOnCurrentChain,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
    reset: resetWrite,
    pendingAction,
    chainId,
    chainLabels: CHAIN_LABELS,
    homeChainId,
    RoundState,
  };
}
