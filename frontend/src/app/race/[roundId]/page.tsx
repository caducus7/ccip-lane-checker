import { BettingPanel } from "@/components/race/BettingPanel";

interface RacePageProps {
  params: Promise<{ roundId: string }>;
}

export default async function RacePage({ params }: RacePageProps) {
  const { roundId } = await params;
  const id = BigInt(roundId);

  return <BettingPanel roundId={id} />;
}
