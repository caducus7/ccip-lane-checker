import { SoloGamePanel } from "@/components/solo/SoloGamePanel";

export default function SoloPage() {
  return (
    <div className="space-y-8">
      <header>
        <span className="font-mono text-[10px] uppercase tracking-[0.3em] text-neon-cyan">
          Mode 01
        </span>
        <h1 className="font-display text-3xl sm:text-4xl tracking-wider uppercase mt-1">
          Solo <span className="text-neon-cyan">Challenge</span>
        </h1>
        <p className="mt-2 font-mono text-sm text-white/50 max-w-2xl">
          One player, one token, random CCIP hops via VRF. Track each hop in
          real time and climb the latency leaderboard.
        </p>
      </header>

      <SoloGamePanel />
    </div>
  );
}
