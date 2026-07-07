import {
  cre,
  handler,
  Runner,
  type CronPayload,
  type HTTPPayload,
  type HTTPSendRequester,
  type Runtime,
  ConsensusAggregationByFields,
  median,
  ok,
  json,
} from "@chainlink/cre-sdk";
import { z } from "zod";

export type LaneRoute = {
  label: string;
  sourceChainSelector: string;
  destChainSelector: string;
};

export type Config = {
  schedule: string;
  ccipApiBaseUrl: string;
  cacheKey: string;
  authorizedKeys: Array<{ publicKey?: string }>;
  lanes: LaneRoute[];
};

const laneLatencySchema = z.object({
  lane: z
    .object({
      sourceNetworkInfo: z
        .object({
          displayName: z.string().optional(),
        })
        .optional(),
      destNetworkInfo: z
        .object({
          displayName: z.string().optional(),
        })
        .optional(),
    })
    .optional(),
  totalMs: z.number().nonnegative(),
});

type LaneLatencyResponse = z.infer<typeof laneLatencySchema>;

type LaneBenchmarkEntry = {
  label: string;
  sourceChainSelector: string;
  destChainSelector: string;
  totalMs?: number;
  sourceName?: string;
  destName?: string;
  fetchedAt: string;
  error?: string;
};

type BenchmarkSnapshot = {
  cacheKey: string;
  fetchedAt: string;
  lanes: LaneBenchmarkEntry[];
};

const latencyAggregation = ConsensusAggregationByFields<LaneLatencyResponse>({
  totalMs: () => median(),
});

const fetchLaneLatencyUrl = (
  sendRequester: HTTPSendRequester,
  url: string,
): LaneLatencyResponse => {
  const response = sendRequester.sendRequest({ url, method: "GET" }).result();

  if (!ok(response)) {
    throw new Error(`CCIP API ${response.statusCode} for ${url}`);
  }

  return laneLatencySchema.parse(json(response));
};

const buildLatencyUrl = (
  baseUrl: string,
  sourceChainSelector: string,
  destChainSelector: string,
): string =>
  `${baseUrl}/lanes/latency` +
  `?sourceChainSelector=${sourceChainSelector}` +
  `&destChainSelector=${destChainSelector}`;

const collectBenchmarks = (runtime: Runtime<Config>): BenchmarkSnapshot => {
  const httpClient = new cre.capabilities.HTTPClient();
  const fetchedAt = runtime.now().toISOString();
  const lanes: LaneBenchmarkEntry[] = [];

  for (const route of runtime.config.lanes) {
    const url = buildLatencyUrl(
      runtime.config.ccipApiBaseUrl,
      route.sourceChainSelector,
      route.destChainSelector,
    );

    try {
      const result = httpClient
        .sendRequest(runtime, fetchLaneLatencyUrl, latencyAggregation)(url)
        .result();

      lanes.push({
        label: route.label,
        sourceChainSelector: route.sourceChainSelector,
        destChainSelector: route.destChainSelector,
        totalMs: result.totalMs,
        sourceName: result.lane?.sourceNetworkInfo?.displayName,
        destName: result.lane?.destNetworkInfo?.displayName,
        fetchedAt,
      });

      runtime.log(
        `lane ${route.label}: p90=${result.totalMs}ms (${route.sourceChainSelector}->${route.destChainSelector})`,
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      lanes.push({
        label: route.label,
        sourceChainSelector: route.sourceChainSelector,
        destChainSelector: route.destChainSelector,
        fetchedAt,
        error: message,
      });
      runtime.log(`lane ${route.label} failed: ${message}`);
    }
  }

  return {
    cacheKey: runtime.config.cacheKey,
    fetchedAt,
    lanes,
  };
};

const onCronTrigger = (
  runtime: Runtime<Config>,
  payload: CronPayload,
): string => {
  const scheduledAt =
    payload.scheduledExecutionTime?.seconds?.toString() ??
    runtime.now().toISOString();
  runtime.log(`lane-benchmark cron at ${scheduledAt}`);

  const snapshot = collectBenchmarks(runtime);
  const output = JSON.stringify(snapshot);
  runtime.log(`benchmark cache[${runtime.config.cacheKey}]: ${output}`);
  return output;
};

const onHttpTrigger = (
  runtime: Runtime<Config>,
  triggerEvent: HTTPPayload,
): string => {
  const bodyText = new TextDecoder().decode(triggerEvent.input);
  runtime.log(`lane-benchmark HTTP refresh: ${bodyText}`);

  const snapshot = collectBenchmarks(runtime);
  const output = JSON.stringify({
    ...snapshot,
    trigger: "http",
    requestBody: bodyText,
  });

  runtime.log(`benchmark HTTP response: ${output}`);
  return output;
};

export const initWorkflow = (config: Config) => {
  const cron = new cre.capabilities.CronCapability();
  const http = new cre.capabilities.HTTPCapability();

  return [
    handler(cron.trigger({ schedule: config.schedule }), onCronTrigger),
    handler(
      http.trigger({ authorizedKeys: config.authorizedKeys }),
      onHttpTrigger,
    ),
  ];
};

export async function main() {
  const runner = await Runner.newRunner<Config>();
  await runner.run(initWorkflow);
}
