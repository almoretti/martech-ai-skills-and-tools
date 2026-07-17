import { Command } from "commander";
import { loadCredentials } from "../auth.js";
import { callApi } from "../api.js";
import { output, fatal, normalizeId, commaList } from "../utils.js";

const ALL_CAMPAIGN_TYPES = "Search,Shopping,Audience,DynamicSearchAds,PerformanceMax";
const CAMPAIGN_ADDITIONAL_FIELDS =
  "AdScheduleUseSearcherTimeZone,BidStrategyId,CpvCpmBiddingScheme,DynamicFeedSetting,MaxConversionValueBiddingScheme,MultimediaAdsBidAdjustment,TargetImpressionShareBiddingScheme,TargetSetting,VerifiedTrackingSetting";

export function registerCampaignCommands(program: Command): void {
  program
    .command("campaigns <account-id>")
    .description("List campaigns for an ad account")
    .option("--type <type>", "Campaign type: Search, Shopping, Audience, DynamicSearchAds, PerformanceMax (default all)")
    .option("--status <status>", "Filter by status: Active, Paused, BudgetPaused, BudgetAndManualPaused, Suspended")
    .action(async (accountId: string, opts) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const id = normalizeId(accountId);
        const data = (await callApi({
          creds,
          service: "campaign",
          path: "Campaigns/QueryByAccountId",
          accountId: id,
          body: {
            AccountId: id,
            CampaignType: opts.type || ALL_CAMPAIGN_TYPES,
            ReturnAdditionalFields: CAMPAIGN_ADDITIONAL_FIELDS,
          },
        })) as Record<string, unknown>;
        if (opts.status && Array.isArray(data.Campaigns)) {
          data.Campaigns = data.Campaigns.filter(
            (c: Record<string, unknown>) => String(c.Status) === opts.status
          );
        }
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("campaign <account-id> <campaign-id>")
    .description("Get a specific campaign")
    .action(async (accountId: string, campaignId: string) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const id = normalizeId(accountId);
        const data = await callApi({
          creds,
          service: "campaign",
          path: "Campaigns/QueryByIds",
          accountId: id,
          body: {
            AccountId: id,
            CampaignIds: [campaignId],
            CampaignType: ALL_CAMPAIGN_TYPES,
            ReturnAdditionalFields: CAMPAIGN_ADDITIONAL_FIELDS,
          },
        });
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("campaign-budgets <account-id>")
    .description("List shared campaign budgets (all budgets in the account)")
    .option("--ids <ids>", "Budget IDs (comma-separated, default all)")
    .action(async (accountId: string, opts) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const data = await callApi({
          creds,
          service: "campaign",
          path: "Budgets/QueryByIds",
          accountId: normalizeId(accountId),
          body: {
            BudgetIds: opts.ids ? commaList(opts.ids) : null,
          },
        });
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("bid-strategies <account-id>")
    .description("List portfolio bid strategies (all in the account)")
    .option("--ids <ids>", "Bid strategy IDs (comma-separated, default all)")
    .action(async (accountId: string, opts) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const data = await callApi({
          creds,
          service: "campaign",
          path: "BidStrategies/QueryByIds",
          accountId: normalizeId(accountId),
          body: {
            BidStrategyIds: opts.ids ? commaList(opts.ids) : null,
          },
        });
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });
}
