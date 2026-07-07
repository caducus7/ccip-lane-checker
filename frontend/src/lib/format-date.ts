/** Fixed-locale UTC formatting so SSR and client hydration match. */
const UTC: Intl.DateTimeFormatOptions = { timeZone: "UTC" };

export function formatUtcTime(iso: string): string {
  return new Date(iso).toLocaleTimeString("en-US", {
    ...UTC,
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  });
}

export function formatUtcDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-US", {
    ...UTC,
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

export function formatUtcDateTime(iso: string): string {
  return new Date(iso).toLocaleString("en-US", {
    ...UTC,
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  });
}
