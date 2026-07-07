import type { BaseError } from "viem";

interface TxFeedbackProps {
  hash?: `0x${string}`;
  error: Error | null;
  isSuccess?: boolean;
  successMessage?: string;
  onDismiss?: () => void;
}

function shortenError(error: Error): string {
  const base = error as BaseError;
  if (base.shortMessage) return base.shortMessage;
  if (error.message.length > 120) {
    return `${error.message.slice(0, 120)}…`;
  }
  return error.message;
}

export function TxFeedback({
  hash,
  error,
  isSuccess,
  successMessage,
  onDismiss,
}: TxFeedbackProps) {
  if (!hash && !error && !isSuccess) return null;

  return (
    <div className="space-y-2">
      {error && (
        <div className="border border-neon-red/40 bg-neon-red/5 px-3 py-2.5 flex items-start justify-between gap-2">
          <p className="font-mono text-[10px] sm:text-xs text-neon-red leading-relaxed">
            {shortenError(error)}
          </p>
          {onDismiss && (
            <button
              type="button"
              onClick={onDismiss}
              className="shrink-0 font-mono text-[10px] text-white/40 hover:text-white"
              aria-label="Dismiss error"
            >
              ✕
            </button>
          )}
        </div>
      )}

      {isSuccess && successMessage && (
        <p className="font-mono text-[10px] sm:text-xs text-neon-lime">
          {successMessage}
        </p>
      )}

      {hash && (
        <p className="font-mono text-[10px] text-white/40 break-all">
          Tx: {hash}
        </p>
      )}
    </div>
  );
}
