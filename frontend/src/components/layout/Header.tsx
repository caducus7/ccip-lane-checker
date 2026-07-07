import Link from "next/link";
import { ConnectButton } from "@/components/wallet/ConnectButton";

const NAV = [
  { href: "/", label: "Pit Lane" },
  { href: "/solo", label: "Solo" },
  { href: "/race/1", label: "Race" },
  { href: "/leaderboard", label: "Standings" },
  { href: "/lanes", label: "Benchmarks" },
];

export function Header() {
  return (
    <header className="sticky top-0 z-50 border-b border-grid/80 bg-asphalt/90 backdrop-blur-md">
      <div className="mx-auto flex max-w-7xl items-center justify-between gap-4 px-4 py-3 sm:px-6">
        <Link href="/" className="group flex items-center gap-3 shrink-0">
          <div className="h-8 w-8 bg-checkered bg-checkered border border-neon-cyan/40 group-hover:border-neon-cyan transition-colors" />
          <div>
            <span className="font-display text-lg tracking-wider text-white">
              LANE<span className="text-neon-cyan">CHECK</span>
            </span>
            <span className="block font-mono text-[10px] uppercase tracking-[0.3em] text-neon-cyan/60">
              CCIP Racing
            </span>
          </div>
        </Link>

        <nav className="hidden md:flex items-center gap-1">
          {NAV.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className="px-3 py-2 font-mono text-xs uppercase tracking-wider text-white/60 hover:text-neon-cyan transition-colors"
            >
              {item.label}
            </Link>
          ))}
        </nav>

        <ConnectButton />
      </div>

      <nav className="flex md:hidden overflow-x-auto border-t border-grid/50 px-2 py-2 gap-1">
        {NAV.map((item) => (
          <Link
            key={item.href}
            href={item.href}
            className="shrink-0 px-3 py-1.5 font-mono text-[10px] uppercase tracking-wider text-white/50 hover:text-neon-cyan"
          >
            {item.label}
          </Link>
        ))}
      </nav>
    </header>
  );
}
