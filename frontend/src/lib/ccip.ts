const CCIP_EXPLORER_BASE = "https://ccip.chain.link";

export function ccipExplorerMessageUrl(messageId: string): string {
  const normalized = messageId.startsWith("0x") ? messageId : `0x${messageId}`;
  return `${CCIP_EXPLORER_BASE}/msg/${normalized}`;
}

export function ccipExplorerTxUrl(txHash: string, chainSlug?: string): string {
  const normalized = txHash.startsWith("0x") ? txHash : `0x${txHash}`;
  if (chainSlug) {
    return `${CCIP_EXPLORER_BASE}/tx/${chainSlug}/${normalized}`;
  }
  return `${CCIP_EXPLORER_BASE}/tx/${normalized}`;
}

export function ccipExplorerHome(): string {
  return CCIP_EXPLORER_BASE;
}

export type MessageStatus = "pending" | "success" | "failure" | "unknown";

export interface CcipMessageStatus {
  messageId: string;
  status: MessageStatus;
  sourceChain?: string;
  destChain?: string;
  latencyMs?: number;
}

/** Placeholder until CCIP API / CRE benchmark cache is wired (Step 6) */
export async function fetchMessageStatus(
  messageId: string
): Promise<CcipMessageStatus> {
  await new Promise((r) => setTimeout(r, 300));
  return {
    messageId,
    status: "pending",
  };
}
