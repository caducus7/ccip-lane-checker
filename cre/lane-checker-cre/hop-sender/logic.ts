import { RoundState } from "./lane-controller-abi";

export type LaneSnapshot = {
  hopsCompleted: number;
  requiredHops: number;
  finished: boolean;
};

export function shouldCronSendInitial(input: {
  isOriginChain: boolean;
  roundId: bigint;
  roundState: number;
}): { proceed: boolean; reason?: string } {
  if (!input.isOriginChain) {
    return { proceed: false, reason: "not-origin-chain" };
  }
  if (input.roundId === 0n) {
    return { proceed: false, reason: "no-rounds" };
  }
  if (input.roundState !== RoundState.Racing) {
    return { proceed: false, reason: "not-racing" };
  }
  return { proceed: true };
}

export function shouldSendHop(
  lane: LaneSnapshot,
  initialOnly: boolean,
): boolean {
  if (lane.finished || lane.hopsCompleted >= lane.requiredHops) {
    return false;
  }
  if (initialOnly && lane.hopsCompleted !== 0) {
    return false;
  }
  return true;
}

export function shouldProcessHopReceived(roundState: number): boolean {
  return (
    roundState === RoundState.Racing || roundState === RoundState.Finished
  );
}
