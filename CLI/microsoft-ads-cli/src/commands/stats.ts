import { Command } from "commander";
import { loadCredentials } from "../auth.js";
import { runReport } from "../report.js";
import { output, fatal, normalizeId, commaList } from "../utils.js";

const SEGMENT_COLUMNS: Record<string, string> = {
  device: "DeviceType",
  network: "Network",
  device_os: "DeviceOS",
  top_vs_other: "TopVsOther",
  bid_match_type: "BidMatchType",
  delivered_match_type: "DeliveredMatchType",
};

function segmentColumns(segments: string | undefined): string[] {
  if (!segments) return [];
  return commaList(segments).map((s) => {
    const col = SEGMENT_COLUMNS[s.toLowerCase()] || s;
    return col;
  });
}

function campaignScope(accountId: string, campaign: string | undefined): Record<string, unknown> | undefined {
  if (!campaign) return undefined;
  return { Campaigns: [{ AccountId: accountId, CampaignId: campaign }] };
}

function adGroupScope(
  accountId: string,
  campaign: string | undefined,
  adGroup: string | undefined
): Record<string, unknown> | undefined {
  if (adGroup) {
    if (!campaign) throw new Error("--ad-group also requires --campaign (Bing report scope needs both)");
    return { AdGroups: [{ AccountId: accountId, CampaignId: campaign, AdGroupId: adGroup }] };
  }
  return campaignScope(accountId, campaign);
}

interface StatsOpts {
  start: string;
  end: string;
  granularity: string;
  segments?: string;
  campaign?: string;
  adGroup?: string;
  timeout: string;
  columns?: string;
}

async function execStats(
  program: Command,
  accountId: string,
  opts: StatsOpts,
  spec: {
    type: string;
    reportName: string;
    defaultColumns: string[];
    scope?: Record<string, unknown>;
  }
): Promise<void> {
  const creds = await loadCredentials(program.opts().credentials);
  const columns = opts.columns
    ? commaList(opts.columns)
    : [...spec.defaultColumns, ...segmentColumns(opts.segments)];
  const { rows, reportRequestId } = await runReport(
    creds,
    {
      type: spec.type,
      reportName: spec.reportName,
      columns,
      aggregation: opts.granularity,
      accountId,
      start: opts.start,
      end: opts.end,
      scope: spec.scope,
    },
    parseInt(opts.timeout)
  );
  output({ reportRequestId, rowCount: rows.length, rows }, program.opts().format);
}

export function registerStatsCommands(program: Command): void {
  program
    .command("campaign-stats <account-id>")
    .description("Get campaign performance stats")
    .requiredOption("--start <date>", "Start date (YYYY-MM-DD)")
    .requiredOption("--end <date>", "End date (YYYY-MM-DD)")
    .option("--campaign <id>", "Filter by campaign ID")
    .option("--segments <segs>", "Additional segments: device, network, device_os, top_vs_other (comma-separated)")
    .option("--granularity <gran>", "Aggregation: Daily, Weekly, Monthly, Summary, Hourly", "Daily")
    .option("--columns <cols>", "Override report columns (comma-separated)")
    .option("--timeout <seconds>", "Max seconds to wait for the report", "120")
    .action(async (accountId: string, opts) => {
      try {
        const id = normalizeId(accountId);
        await execStats(program, id, opts, {
          type: "CampaignPerformanceReportRequest",
          reportName: "CampaignPerformanceReport",
          defaultColumns: [
            "TimePeriod", "AccountId", "CampaignId", "CampaignName", "CampaignStatus",
            "Impressions", "Clicks", "Ctr", "Spend", "AverageCpc",
            "Conversions", "ConversionRate", "CostPerConversion", "Revenue",
          ],
          scope: campaignScope(id, opts.campaign),
        });
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("ad-group-stats <account-id>")
    .description("Get ad group performance stats")
    .requiredOption("--start <date>", "Start date (YYYY-MM-DD)")
    .requiredOption("--end <date>", "End date (YYYY-MM-DD)")
    .option("--campaign <id>", "Filter by campaign ID")
    .option("--ad-group <id>", "Filter by ad group ID (requires --campaign)")
    .option("--segments <segs>", "Additional segments: device, network, device_os, top_vs_other (comma-separated)")
    .option("--granularity <gran>", "Aggregation: Daily, Weekly, Monthly, Summary, Hourly", "Daily")
    .option("--columns <cols>", "Override report columns (comma-separated)")
    .option("--timeout <seconds>", "Max seconds to wait for the report", "120")
    .action(async (accountId: string, opts) => {
      try {
        const id = normalizeId(accountId);
        await execStats(program, id, opts, {
          type: "AdGroupPerformanceReportRequest",
          reportName: "AdGroupPerformanceReport",
          defaultColumns: [
            "TimePeriod", "AccountId", "CampaignId", "CampaignName",
            "AdGroupId", "AdGroupName", "Status",
            "Impressions", "Clicks", "Ctr", "Spend", "AverageCpc",
            "Conversions", "ConversionRate", "CostPerConversion",
          ],
          scope: adGroupScope(id, opts.campaign, opts.adGroup),
        });
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("ad-stats <account-id>")
    .description("Get ad-level performance stats")
    .requiredOption("--start <date>", "Start date (YYYY-MM-DD)")
    .requiredOption("--end <date>", "End date (YYYY-MM-DD)")
    .option("--campaign <id>", "Filter by campaign ID")
    .option("--ad-group <id>", "Filter by ad group ID (requires --campaign)")
    .option("--segments <segs>", "Additional segments: device, network, device_os, top_vs_other (comma-separated)")
    .option("--granularity <gran>", "Aggregation: Daily, Weekly, Monthly, Summary, Hourly", "Daily")
    .option("--columns <cols>", "Override report columns (comma-separated)")
    .option("--timeout <seconds>", "Max seconds to wait for the report", "120")
    .action(async (accountId: string, opts) => {
      try {
        const id = normalizeId(accountId);
        await execStats(program, id, opts, {
          type: "AdPerformanceReportRequest",
          reportName: "AdPerformanceReport",
          defaultColumns: [
            "TimePeriod", "AccountId", "CampaignId", "CampaignName",
            "AdGroupId", "AdGroupName", "AdId", "AdTitle", "AdType", "AdStatus",
            "Impressions", "Clicks", "Ctr", "Spend", "AverageCpc", "Conversions",
          ],
          scope: adGroupScope(id, opts.campaign, opts.adGroup),
        });
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("keyword-stats <account-id>")
    .description("Get keyword-level performance stats")
    .requiredOption("--start <date>", "Start date (YYYY-MM-DD)")
    .requiredOption("--end <date>", "End date (YYYY-MM-DD)")
    .option("--campaign <id>", "Filter by campaign ID")
    .option("--ad-group <id>", "Filter by ad group ID (requires --campaign)")
    .option("--segments <segs>", "Additional segments: device, network, bid_match_type, delivered_match_type (comma-separated)")
    .option("--granularity <gran>", "Aggregation: Daily, Weekly, Monthly, Summary, Hourly", "Daily")
    .option("--columns <cols>", "Override report columns (comma-separated)")
    .option("--timeout <seconds>", "Max seconds to wait for the report", "120")
    .action(async (accountId: string, opts) => {
      try {
        const id = normalizeId(accountId);
        await execStats(program, id, opts, {
          type: "KeywordPerformanceReportRequest",
          reportName: "KeywordPerformanceReport",
          defaultColumns: [
            "TimePeriod", "AccountId", "CampaignId", "CampaignName",
            "AdGroupId", "AdGroupName", "Keyword", "KeywordId", "KeywordStatus",
            "Impressions", "Clicks", "Ctr", "Spend", "AverageCpc",
            "Conversions", "QualityScore",
          ],
          scope: adGroupScope(id, opts.campaign, opts.adGroup),
        });
      } catch (err) {
        fatal((err as Error).message);
      }
    });
}
