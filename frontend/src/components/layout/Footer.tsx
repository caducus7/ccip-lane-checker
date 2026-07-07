import { ccipExplorerHome } from "@/lib/ccip";

export function Footer() {
  return (
    <footer className="mt-auto border-t border-grid/60 bg-asphalt-100">
      <div className="mx-auto flex max-w-7xl flex-col gap-3 px-4 py-6 sm:flex-row sm:items-center sm:justify-between sm:px-6">
        <p className="font-mono text-xs text-white/40">
          CCIP Lane Checker — testnet demo. Contracts not yet deployed.
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
