import type { Credentials } from "./auth.js";
import { callApi } from "./api.js";
import { unzipFirstEntry, parseCsv, csvToObjects } from "./utils.js";

export interface ReportSpec {
  type: string;
  reportName: string;
  columns: string[];
  aggregation: string;
  accountId: string;
  start: string; // YYYY-MM-DD
  end: string; // YYYY-MM-DD
  scope?: Record<string, unknown>;
}

function toDate(d: string): { Year: number; Month: number; Day: number } {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(d);
  if (!m) throw new Error(`Invalid date "${d}" (expected YYYY-MM-DD)`);
  return { Year: Number(m[1]), Month: Number(m[2]), Day: Number(m[3]) };
}

export function buildReportRequest(spec: ReportSpec): Record<string, unknown> {
  return {
    ReportRequest: {
      Type: spec.type,
      ExcludeColumnHeaders: false,
      ExcludeReportFooter: true,
      ExcludeReportHeader: true,
      Format: "Csv",
      FormatVersion: "2.0",
      ReportName: spec.reportName,
      ReturnOnlyCompleteData: false,
      Aggregation: spec.aggregation,
      Columns: spec.columns,
      Scope: spec.scope ?? { AccountIds: [spec.accountId] },
      Time: {
        CustomDateRangeStart: toDate(spec.start),
        CustomDateRangeEnd: toDate(spec.end),
      },
    },
  };
}

export async function submitReport(creds: Credentials, spec: ReportSpec): Promise<string> {
  const data = (await callApi({
    creds,
    service: "reporting",
    path: "GenerateReport/Submit",
    accountId: spec.accountId,
    body: buildReportRequest(spec),
  })) as Record<string, unknown>;
  const id = data.ReportRequestId;
  if (!id) throw new Error(`Report submission did not return a ReportRequestId: ${JSON.stringify(data)}`);
  return String(id);
}

export interface PollResult {
  status: string;
  downloadUrl?: string;
}

export async function pollReport(creds: Credentials, reportRequestId: string, accountId?: string): Promise<PollResult> {
  const data = (await callApi({
    creds,
    service: "reporting",
    path: "GenerateReport/Poll",
    accountId,
    body: { ReportRequestId: reportRequestId },
  })) as Record<string, unknown>;
  const status = (data.ReportRequestStatus ?? {}) as Record<string, unknown>;
  return {
    status: String(status.Status ?? "Unknown"),
    downloadUrl: status.ReportDownloadUrl ? String(status.ReportDownloadUrl) : undefined,
  };
}

export async function downloadReport(downloadUrl: string): Promise<Record<string, string>[]> {
  const res = await fetch(downloadUrl);
  if (!res.ok) throw new Error(`Report download failed: HTTP ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  const csv = unzipFirstEntry(buf).toString("utf-8");
  return csvToObjects(parseCsv(csv));
}

const SLEEP_MS = 2000;

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

/** Submit a report, poll until done, download and parse it. Returns JSON rows. */
export async function runReport(
  creds: Credentials,
  spec: ReportSpec,
  timeoutSeconds: number
): Promise<{ rows: Record<string, string>[]; reportRequestId: string }> {
  const reportRequestId = await submitReport(creds, spec);
  const deadline = Date.now() + timeoutSeconds * 1000;

  for (;;) {
    const poll = await pollReport(creds, reportRequestId, spec.accountId);
    if (poll.status === "Success") {
      // No download URL on success means the report has no data
      const rows = poll.downloadUrl ? await downloadReport(poll.downloadUrl) : [];
      return { rows, reportRequestId };
    }
    if (poll.status === "Error") {
      throw new Error(`Report ${reportRequestId} failed with status Error`);
    }
    if (Date.now() > deadline) {
      throw new Error(
        `Report ${reportRequestId} timed out after ${timeoutSeconds}s (status: ${poll.status}). ` +
        `Check it later with: microsoft-ads-cli report-download ${reportRequestId}`
      );
    }
    await sleep(SLEEP_MS);
  }
}
