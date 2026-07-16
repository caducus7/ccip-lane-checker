"use client";

import Link from "next/link";
import { useHomeRoundCounter } from "@/hooks/useHomeLaneController";

export function RaceNavLink({
  className,
}: {
  className?: string;
}) {
  const { data: currentRoundId } = useHomeRoundCounter();
  const href =
    currentRoundId && currentRoundId > 0n
      ? `/race/${currentRoundId.toString()}`
      : "/race/1";

  return (
    <Link href={href} className={className}>
      Race
    </Link>
  );
}
