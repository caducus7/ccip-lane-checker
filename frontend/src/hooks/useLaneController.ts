"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { parseUnits } from "viem";
import {
  erc20Abi,
  getDeploymentByChainId,
  getHomeLaneController,
  HOME_CHAIN_ID,
  isDeployed,
  laneControllerAbi,
} from "@/lib/contracts";
import { useTokenDecimals } from "@/hooks/useTokenDecimals";
import { useTokenAllowance } from "@/hooks/useTokenAllowance";

export type LaneControllerAction = "approve" | "buy" | "claim" | null;

export {
  useHomeRoundCounter as useRoundCounter,
  useHomeRoundState as useRoundState,
  useHomeRoundWinner as useRoundWinner,
  useHomeLanePool as useLanePool,
  useHomeTotalPrizePool as useTotalPrizePool,
  useHomeLane as useLane,
} from "@/hooks/useHomeLaneController";

export function useLaneControllerActions() {
  const { chainId } = useAccount();
  const controller = getHomeLaneController();
  const homeDeployment = getDeploymentByChainId(HOME_CHAIN_ID);
  const bettingToken = homeDeployment?.underlyingToken;
  const { data: decimals } = useTokenDecimals(bettingToken, HOME_CHAIN_ID);
  const { data: allowance, refetch: refetchAllowance } = useTokenAllowance(
    bettingToken,
    controller,
    HOME_CHAIN_ID,
  );

  const [pendingAction, setPendingAction] = useState<LaneControllerAction>(null);
  const [lastCompletedAction, setLastCompletedAction] =
    useState<LaneControllerAction>(null);

  const {
    writeContract,
    data: hash,
    isPending,
    error,
    reset: resetWrite,
  } = useWriteContract();

  const resetWriteRef = useRef(resetWrite);
  resetWriteRef.current = resetWrite;

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  const onHomeChain = chainId === HOME_CHAIN_ID;

  useEffect(() => {
    if (!isSuccess || !pendingAction) return;
    setLastCompletedAction(pendingAction);
    void refetchAllowance();
    setPendingAction(null);
  }, [isSuccess, pendingAction, refetchAllowance]);

  const needsApproval = (amount: string): boolean => {
    if (decimals === undefined || allowance === undefined) return true;
    try {
      return allowance < parseUnits(amount, decimals);
    } catch {
      return true;
    }
  };

  const approveBettingToken = (amount: string) => {
    if (
      !bettingToken ||
      !controller ||
      !isDeployed(controller) ||
      decimals === undefined ||
      !onHomeChain
    ) {
      return;
    }
    setPendingAction("approve");
    writeContract({
      chainId: HOME_CHAIN_ID,
      address: bettingToken,
      abi: erc20Abi,
      functionName: "approve",
      args: [controller, parseUnits(amount, decimals)],
    });
  };

  const buyLaneTokens = (
    roundId: bigint,
    laneId: number,
    amount: string,
  ) => {
    if (
      !controller ||
      !isDeployed(controller) ||
      decimals === undefined ||
      !onHomeChain
    ) {
      return;
    }
    setPendingAction("buy");
    writeContract({
      chainId: HOME_CHAIN_ID,
      address: controller,
      abi: laneControllerAbi,
      functionName: "buyLaneTokens",
      args: [roundId, laneId, parseUnits(amount, decimals)],
    });
  };

  const claimPrize = (roundId: bigint) => {
    if (!controller || !isDeployed(controller) || !onHomeChain) return;
    setPendingAction("claim");
    writeContract({
      chainId: HOME_CHAIN_ID,
      address: controller,
      abi: laneControllerAbi,
      functionName: "claimPrize",
      args: [roundId],
    });
  };

  const clearActionState = useCallback(() => {
    resetWriteRef.current();
    setPendingAction(null);
    setLastCompletedAction(null);
  }, []);

  return {
    approveBettingToken,
    buyLaneTokens,
    claimPrize,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
    reset: clearActionState,
    pendingAction,
    lastCompletedAction,
    needsApproval,
    allowance,
    isDeployed: isDeployed(controller),
    bettingToken,
    decimals,
    onHomeChain,
    homeChainId: HOME_CHAIN_ID,
  };
}

/** RoundState enum: 0=Betting, 1=Racing, 2=Finished, 3=Settled */
export const RoundStateLabel: Record<number, string> = {
  0: "betting",
  1: "racing",
  2: "finished",
  3: "settled",
};
