import { Command } from "commander";
import { loadCredentials } from "../auth.js";
import { callApi } from "../api.js";
import { output, fatal, normalizeId } from "../utils.js";

const ADGROUP_ADDITIONAL_FIELDS =
  "AdScheduleUseSearcherTimeZone,CpmBid,CpvBid,MultimediaAdsBidAdjustment";
const ALL_AD_TYPES = [
  "AppInstall",
  "DynamicSearch",
  "ExpandedText",
  "Hotel",
  "Product",
  "ResponsiveAd",
  "ResponsiveSearch",
];

export function registerAdGroupCommands(program: Command): void {
  program
    .command("ad-groups <account-id> <campaign-id>")
    .description("List ad groups for a campaign")
    .action(async (accountId: string, campaignId: string) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const data = await callApi({
          creds,
          service: "campaign",
          path: "AdGroups/QueryByCampaignId",
          accountId: normalizeId(accountId),
          body: {
            CampaignId: campaignId,
            ReturnAdditionalFields: ADGROUP_ADDITIONAL_FIELDS,
          },
        });
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("ad-group <account-id> <campaign-id> <ad-group-id>")
    .description("Get a specific ad group")
    .action(async (accountId: string, campaignId: string, adGroupId: string) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const data = await callApi({
          creds,
          service: "campaign",
          path: "AdGroups/QueryByIds",
          accountId: normalizeId(accountId),
          body: {
            CampaignId: campaignId,
            AdGroupIds: [adGroupId],
            ReturnAdditionalFields: ADGROUP_ADDITIONAL_FIELDS,
          },
        });
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("ads <account-id> <ad-group-id>")
    .description("List ads for an ad group")
    .option("--type <type>", "Ad types (comma-separated): AppInstall, DynamicSearch, ExpandedText, Hotel, Product, ResponsiveAd, ResponsiveSearch (default all)")
    .action(async (accountId: string, adGroupId: string, opts) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const data = await callApi({
          creds,
          service: "campaign",
          path: "Ads/QueryByAdGroupId",
          accountId: normalizeId(accountId),
          body: {
            AdGroupId: adGroupId,
            AdTypes: opts.type
              ? opts.type.split(",").map((t: string) => t.trim())
              : ALL_AD_TYPES,
          },
        });
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("ad <account-id> <ad-group-id> <ad-id>")
    .description("Get a specific ad")
    .action(async (accountId: string, adGroupId: string, adId: string) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const data = await callApi({
          creds,
          service: "campaign",
          path: "Ads/QueryByIds",
          accountId: normalizeId(accountId),
          body: {
            AdGroupId: adGroupId,
            AdIds: [adId],
            // Omitting AdTypes makes the API fail with a misleading
            // "Creating or updating ads of this type is not allowed."
            AdTypes: ALL_AD_TYPES,
          },
        });
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });
}
