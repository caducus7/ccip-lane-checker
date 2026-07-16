import { ccipExplorerHome } from "@/lib/ccip";
import { hasAnyDeployment } from "@/lib/contracts";

export function Footer() {
  const live = hasAnyDeployment();

  return (
    <footer className="mt-auto border-t border-grid/60 bg-asphalt-100">
      <div className="mx-auto flex max-w-7xl flex-col gap-3 px-4 py-6 sm:flex-row sm:items-center sm:justify-between sm:px-6">
        <p className="font-mono text-xs text-white/40">
          {live
            ? "CCIP Lane Checker — Sepolia / Arbitrum Sepolia / Base Sepolia."
            : "CCIP Lane Checker — testnet demo. Deploy addresses pending in testnet.json."}
        </p>
        <a
          href={ccipExplorerHome()}
          target="_blank"
          rel="noopener noreferrer"
          className="font-mono text-xs uppercase tracking-wider text-neon-cyan/70 hover:text-neon-cyan transition-colors"
        >
          CCIP Explorer →
        </a>
      </div>
    </footer>
  );
}
