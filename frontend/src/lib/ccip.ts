import { selectorToChainId, CHAIN_SHORT, type SupportedChainId } from "./chains";

const CCIP_EXPLORER_BASE = "https://ccip.chain.link";

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
