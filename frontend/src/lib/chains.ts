import { sepolia, arbitrumSepolia } from "viem/chains";

export const SUPPORTED_CHAINS = [sepolia, arbitrumSepolia] as const;

export type SupportedChainId = (typeof SUPPORTED_CHAINS)[number]["id"];

export const CCIP_CHAIN_SELECTORS: Record<SupportedChainId, bigint> = {
  [sepolia.id]: 16015286601757825753n,
  [arbitrumSepolia.id]: 3478487238524512106n,
};

export const CHAIN_LABELS: Record<SupportedChainId, string> = {
  [sepolia.id]: "Ethereum Sepolia",
  [arbitrumSepolia.id]: "Arbitrum Sepolia",
};

export const CHAIN_SHORT: Record<SupportedChainId, string> = {
  [sepolia.id]: "SEP",
  [arbitrumSepolia.id]: "ARB",
};

export function selectorToChainId(selector: bigint): SupportedChainId | null {
  for (const [chainId, sel] of Object.entries(CCIP_CHAIN_SELECTORS)) {
    if (sel === selector) return Number(chainId) as SupportedChainId;
  }
  return null;
}

export function chainIdToSelector(chainId: SupportedChainId): bigint {
  return CCIP_CHAIN_SELECTORS[chainId];
}
