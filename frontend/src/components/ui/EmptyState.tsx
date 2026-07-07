import type { ReactNode } from "react";
import Link from "next/link";

type EmptyStateVariant = "info" | "warning" | "error";

interface EmptyStateProps {
  title: string;
  description: string;
  variant?: EmptyStateVariant;
  action?: { label: string; href: string };
  children?: ReactNode;
}

const VARIANT_STYLES: Record<
  EmptyStateVariant,
  { border: string; bg: string; title: string }
> = {
  info: {
    border: "border-neon-cyan/30",
    bg: "bg-neon-cyan/5",
    title: "text-neon-cyan",
  },
  warning: {
    border: "border-neon-amber/40",
    bg: "bg-neon-amber/5",
    title: "text-neon-amber",
  },
  error: {
    border: "border-neon-red/40",
    bg: "bg-neon-red/5",
    title: "text-neon-red",
  },
};

export function EmptyState({
  title,
  description,
  variant = "info",
  action,
  children,
}: EmptyStateProps) {
  const styles = VARIANT_STYLES[variant];

  return (
    <div
      className={`border ${styles.border} ${styles.bg} px-4 py-5 sm:px-6 sm:py-6`}
      role="status"
    >
      <p
        className={`font-display text-sm sm:text-base tracking-widest uppercase ${styles.title}`}
      >
        {title}
      </p>
      <p className="mt-2 font-mono text-xs sm:text-sm text-white/50 leading-relaxed max-w-2xl">
        {description}
      </p>
      {children}
      {action && (
        <Link
          href={action.href}
          className="inline-block mt-4 px-4 py-2 font-mono text-[10px] uppercase tracking-[0.2em] border border-grid text-white/60 hover:border-neon-cyan/50 hover:text-neon-cyan transition-colors"
        >
          {action.label}
        </Link>
      )}
    </div>
  );
}

export function DeploymentBanner({
  contractName = "Contracts",
}: {
  contractName?: string;
}) {
  return (
    <EmptyState
      variant="warning"
      title={`${contractName} not deployed`}
      description="Testnet addresses are empty in contracts/deployments/testnet.json. Demo data is shown until Step 4 deploy fills live addresses."
      action={{ label: "View benchmarks", href: "/lanes" }}
    />
  );
}

export function NoActiveRoundState() {
  return (
    <EmptyState
      variant="info"
      title="No active round"
      description="There is no parimutuel round open for betting right now. Check back after the CRE round-scheduler creates the next race, or explore solo challenge mode."
      action={{ label: "Solo challenge", href: "/solo" }}
    />
  );
}
