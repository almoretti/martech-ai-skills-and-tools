import { Command } from "commander";
import { loadCredentials } from "../auth.js";
import { callApi, BASE_URLS } from "../api.js";
import type { ServiceName } from "../api.js";
import { runReport, submitReport, pollReport, downloadReport } from "../report.js";
import { output, fatal, normalizeId, commaList } from "../utils.js";

/** Only allow read operations through the raw escape hatch. */
function assertReadOnly(path: string): void {
  const lastSegment = path.split("/").pop() || "";
  const readOnly =
    /^(Query|Search|Poll)/i.test(lastSegment) || path.startsWith("GenerateReport/");
  if (!readOnly) {
    throw new Error(
      `Refusing to call "${path}": only read operations (Query*, Search, GenerateReport/*) are allowed. ` +
      `This CLI is read-only by design.`
    );
  }
}

export function registerQueryCommands(program: Command): void {
  program
    .command("api <service> <path>")
    .description("Call any read-only Bing Ads REST operation (escape hatch). Services: campaign, customer, reporting, adInsight, bulk")
    .option("--body <json>", "JSON request body", "{}")
    .option("--account-id <id>", "CustomerAccountId header override")
    .option("--customer-id <id>", "CustomerId header override")
    .action(async (service: string, path: string, opts) => {
      try {
        if (!(service in BASE_URLS)) {
          throw new Error(`Unknown service "${service}". Use one of: ${Object.keys(BASE_URLS).join(", ")}`);
        }
        assertReadOnly(path);
        let body: Record<string, unknown>;
        try {
          body = JSON.parse(opts.body);
        } catch {
          throw new Error(`--body is not valid JSON: ${opts.body}`);
        }
        const creds = await loadCredentials(program.opts().credentials);
        const data = await callApi({
          creds,
          service: service as ServiceName,
          path,
          body,
          accountId: opts.accountId,
          customerId: opts.customerId,
        });
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("report <account-id>")
    .description("Run any Bing report type and get parsed JSON rows (generic reporting escape hatch)")
    .requiredOption("--type <type>", "Report request type, e.g. SearchQueryPerformanceReportRequest, AgeGenderAudienceReportRequest")
    .requiredOption("--columns <cols>", "Report columns (comma-separated)")
    .requiredOption("--start <date>", "Start date (YYYY-MM-DD)")
    .requiredOption("--end <date>", "End date (YYYY-MM-DD)")
    .option("--granularity <gran>", "Aggregation: Daily, Weekly, Monthly, Summary, Hourly", "Daily")
    .option("--timeout <seconds>", "Max seconds to wait for the report", "120")
    .option("--async", "Submit only and return the ReportRequestId without waiting")
    .action(async (accountId: string, opts) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const id = normalizeId(accountId);
        const spec = {
          type: opts.type,
          reportName: opts.type.replace(/Request$/, ""),
          columns: commaList(opts.columns),
          aggregation: opts.granularity,
          accountId: id,
          start: opts.start,
          end: opts.end,
        };
        if (opts.async) {
          const reportRequestId = await submitReport(creds, spec);
          output({ reportRequestId }, program.opts().format);
          return;
        }
        const { rows, reportRequestId } = await runReport(creds, spec, parseInt(opts.timeout));
        output({ reportRequestId, rowCount: rows.length, rows }, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("report-status <report-id>")
    .description("Check the status of a submitted report")
    .option("--account-id <id>", "Ad account ID")
    .action(async (reportId: string, opts) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const status = await pollReport(creds, reportId, opts.accountId);
        output(status, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("report-download <report-id>")
    .description("Download and parse a completed report to JSON rows")
    .option("--account-id <id>", "Ad account ID")
    .action(async (reportId: string, opts) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const status = await pollReport(creds, reportId, opts.accountId);
        if (status.status !== "Success") {
          throw new Error(`Report is not ready (status: ${status.status})`);
        }
        const rows = status.downloadUrl ? await downloadReport(status.downloadUrl) : [];
        output({ reportRequestId: reportId, rowCount: rows.length, rows }, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });
}
