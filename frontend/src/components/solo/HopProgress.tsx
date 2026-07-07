"use client";

import { formatEther } from "viem";
import { useAccount } from "wagmi";
import { useGameRound } from "@/hooks/useLaneToken";
import { useCcipMessageStatus } from "@/hooks/useCcipMessageStatus";
import { buildCcipExplorerMessageUrl, type MessageStatus } from "@/lib/ccip";
import { chainIdToSelector } from "@/lib/chains";
import type { SupportedChainId } from "@/lib/chains";
import { LaneRaceViz } from "@/components/race/LaneRaceViz";
import { Skeleton } from "@/components/ui/Skeleton";

interface HopProgressProps {
  gameId: bigint | undefined;
  /** CCIP messageId from BridgeStarted / sendHop events (wired later). */
  messageId?: string;
}

const STATUS_LABEL: Record<MessageStatus, string> = {
  pending: "In flight",
  success: "Delivered",
  failure: "Failed",
  unknown: "Awaiting index",
};

const STATUS_CLASS: Record<MessageStatus, string> = {
  pending: "border-neon-amber text-neon-amber",
  success: "border-neon-lime text-neon-lime",
  failure: "border-neon-red text-neon-red",
  unknown: "border-white/30 text-white/50",
};

export function HopProgress({ gameId, messageId }: HopProgressProps) {
  const { chainId } = useAccount();
  const { data: round, isLoading, isError } = useGameRound(gameId);
  const { data: messageStatus, isFetching: isPollingMessage } =
    useCcipMessageStatus(messageId);

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
    return <Skeleton className="min-h-[280px] w-full border border-grid" />;
  }

  if (isError || !round) {
    return (
      <div className="border border-grid bg-asphalt-50 p-6">
        <p className="font-mono text-sm text-neon-amber">
          Game #{gameId.toString()} — awaiting on-chain data
          {isError ? " (contract not deployed)" : ""}
        </p>
        <MessageStatusPanel
          messageId={messageId}
          messageStatus={messageStatus}
          isPolling={isPollingMessage}
          demo
        />
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
  const sourceSelector =
    chainId !== undefined
      ? chainIdToSelector(chainId as SupportedChainId)
      : 0n;
  const explorerMessageId =
    messageId ?? messageStatus?.messageId ?? "0x" + "0".repeat(64);
  const explorerUrl = buildCcipExplorerMessageUrl(
    sourceSelector,
    explorerMessageId
  );

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

        <MessageStatusPanel
          messageId={messageId}
          messageStatus={messageStatus}
          isPolling={isPollingMessage}
        />

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
                href={explorerUrl}
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

function MessageStatusPanel({
  messageId,
  messageStatus,
  isPolling,
  demo,
}: {
  messageId?: string;
  messageStatus?: { status: MessageStatus; sourceChain?: string; destChain?: string };
  isPolling: boolean;
  demo?: boolean;
}) {
  if (!messageId) {
    return (
      <p className="mb-4 font-mono text-[10px] text-white/40 uppercase tracking-wider">
        {demo
          ? "CCIP message polling — start a race to attach messageId from events"
          : "Hop messageId will appear after the first CCIP send"}
      </p>
    );
  }

  const status = messageStatus?.status ?? "pending";

  return (
    <div className="mb-4 border border-grid bg-asphalt px-3 py-2.5 space-y-1.5">
      <div className="flex items-center justify-between gap-2">
        <span className="font-mono text-[10px] uppercase tracking-widest text-white/40">
          CCIP message
        </span>
        <span
          className={`font-mono text-[10px] uppercase tracking-widest px-2 py-0.5 border ${STATUS_CLASS[status]}`}
        >
          {STATUS_LABEL[status]}
          {isPolling && status === "pending" ? " …" : ""}
        </span>
      </div>
      <p className="font-mono text-[10px] text-white/50 truncate" title={messageId}>
        {messageId}
      </p>
      {(messageStatus?.sourceChain || messageStatus?.destChain) && (
        <p className="font-mono text-[10px] text-white/40">
          {messageStatus.sourceChain ?? "?"} → {messageStatus.destChain ?? "?"}
        </p>
      )}
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
