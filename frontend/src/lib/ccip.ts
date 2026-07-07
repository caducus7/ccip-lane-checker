import { selectorToChainId, CHAIN_SHORT, type SupportedChainId } from "./chains";

const CCIP_EXPLORER_BASE = "https://ccip.chain.link";
const CCIP_API_BASE = "https://api.ccip.chain.link/v2";

export function normalizeMessageId(messageId: string): string {
  return messageId.startsWith("0x") ? messageId : `0x${messageId}`;
}

export function normalizeChainSelector(
  chainSelector: bigint | string | number
): string {
  if (typeof chainSelector === "bigint") return chainSelector.toString();
  if (typeof chainSelector === "number") return chainSelector.toString();
  return chainSelector.replace(/^0x/i, "");
}

/** Map a CCIP chain selector to a short explorer slug (SEP, ARB, …). */
export function chainSelectorToExplorerSlug(
  chainSelector: bigint | string | number
): string {
  const selector =
    typeof chainSelector === "bigint"
      ? chainSelector
      : BigInt(normalizeChainSelector(chainSelector));
  const chainId = selectorToChainId(selector);
  if (chainId) return CHAIN_SHORT[chainId as SupportedChainId].toLowerCase();
  return normalizeChainSelector(chainSelector);
}

/**
 * Build a CCIP Explorer deep link for a message on a specific source chain.
 * Uses lane slug when the selector is known; falls back to raw selector.
 */
export function buildCcipExplorerMessageUrl(
  chainSelector: bigint | string | number,
  messageId: string
): string {
  const slug = chainSelectorToExplorerSlug(chainSelector);
  const normalized = normalizeMessageId(messageId);
  return `${CCIP_EXPLORER_BASE}/msg/${slug}/${normalized}`;
}

export function ccipExplorerMessageUrl(messageId: string): string {
  return `${CCIP_EXPLORER_BASE}/msg/${normalizeMessageId(messageId)}`;
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

interface CcipApiMessage {
  messageId?: string;
  status?: string;
  metadata?: { status?: string };
  sourceChain?: { name?: string };
  destChain?: { name?: string };
}

function mapApiStatus(raw?: string): MessageStatus {
  if (!raw) return "unknown";
  const upper = raw.toUpperCase();
  if (upper.includes("SUCCESS") || upper === "EXECUTED") return "success";
  if (upper.includes("FAIL")) return "failure";
  if (
    upper.includes("PEND") ||
    upper === "SENT" ||
    upper === "IN_FLIGHT" ||
    upper === "ROUTED"
  ) {
    return "pending";
  }
  return "unknown";
}

/** Poll CCIP Tools API for message lifecycle status. */
export async function fetchMessageStatus(
  messageId: string
): Promise<CcipMessageStatus> {
  const normalized = normalizeMessageId(messageId);

  try {
    const res = await fetch(`${CCIP_API_BASE}/messages/${normalized}`, {
      headers: { Accept: "application/json" },
    });

    if (res.status === 404) {
      return { messageId: normalized, status: "pending" };
    }

    if (!res.ok) {
      return { messageId: normalized, status: "unknown" };
    }

    const data = (await res.json()) as CcipApiMessage;
    return {
      messageId: normalized,
      status: mapApiStatus(data.metadata?.status ?? data.status),
      sourceChain: data.sourceChain?.name,
      destChain: data.destChain?.name,
    };
  } catch {
    return { messageId: normalized, status: "pending" };
  }
}
