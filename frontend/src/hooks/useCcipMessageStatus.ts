"use client";

import { useQuery } from "@tanstack/react-query";
import {
  fetchMessageStatus,
  type CcipMessageStatus,
  type MessageStatus,
} from "@/lib/ccip";

const TERMINAL_STATUSES: MessageStatus[] = ["success", "failure"];

export interface UseCcipMessageStatusOptions {
  enabled?: boolean;
  pollIntervalMs?: number;
}

export function useCcipMessageStatus(
  messageId: string | undefined,
  options: UseCcipMessageStatusOptions = {}
) {
  const { enabled = true, pollIntervalMs = 5000 } = options;

  return useQuery<CcipMessageStatus>({
    queryKey: ["ccip-message-status", messageId],
    queryFn: () => fetchMessageStatus(messageId!),
    enabled: enabled && !!messageId,
    refetchInterval: (query) => {
      const status = query.state.data?.status;
      if (status && TERMINAL_STATUSES.includes(status)) return false;
      return pollIntervalMs;
    },
    staleTime: 2000,
  });
}
