import { Command } from "commander";
import { loadCredentials } from "../auth.js";
import { callApi } from "../api.js";
import { output, fatal, normalizeId, commaList } from "../utils.js";

const ALL_EXTENSION_TYPES =
  "ActionAdExtension,AppAdExtension,CallAdExtension,CalloutAdExtension,DisclaimerAdExtension,FilterLinkAdExtension,FlyerAdExtension,ImageAdExtension,LocationAdExtension,LogoAdExtension,PriceAdExtension,PromotionAdExtension,ReviewAdExtension,SitelinkAdExtension,StructuredSnippetAdExtension,VideoAdExtension";

// InStoreTransaction is rejected by the v13 REST GetConversionGoalsByIds
// (the whole query silently returns zero goals when it's included).
const ALL_GOAL_TYPES =
  "Url,Duration,PagesViewedPerVisit,Event,AppInstall,OfflineConversion";

export function registerAssetCommands(program: Command): void {
  program
    .command("extensions <account-id>")
    .description("List ad extensions in the account's extension library")
    .option("--type <type>", "Extension types (comma-separated), e.g. SitelinkAdExtension, CalloutAdExtension, ImageAdExtension (default all)")
    .action(async (accountId: string, opts) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const id = normalizeId(accountId);
        const typeFilter = opts.type ? commaList(opts.type).join(",") : ALL_EXTENSION_TYPES;
        const idsData = (await callApi({
          creds,
          service: "campaign",
          path: "AdExtensionIds/QueryByAccountId",
          accountId: id,
          body: {
            AccountId: id,
            AdExtensionType: typeFilter,
            AssociationType: null,
          },
        })) as Record<string, unknown>;
        const extensionIds = (idsData.AdExtensionIds ?? []) as unknown[];
        if (extensionIds.length === 0) {
          output({ AdExtensions: [] }, program.opts().format);
          return;
        }
        // GetAdExtensionsByIds accepts max 100 ids per call
        const extensions: unknown[] = [];
        for (let i = 0; i < extensionIds.length; i += 100) {
          const batch = (await callApi({
            creds,
            service: "campaign",
            path: "AdExtensions/QueryByIds",
            accountId: id,
            body: {
              AccountId: id,
              AdExtensionIds: extensionIds.slice(i, i + 100),
              AdExtensionType: typeFilter,
            },
          })) as Record<string, unknown>;
          extensions.push(...(((batch.AdExtensions ?? []) as unknown[]).filter(Boolean)));
        }
        output({ AdExtensions: extensions }, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("extension-associations <account-id>")
    .description("List ad extension associations for campaigns or ad groups")
    .requiredOption("--ids <ids>", "Campaign or ad group IDs (comma-separated)")
    .option("--entity <entity>", "Association level: Campaign, AdGroup, Account", "Campaign")
    .option("--type <type>", "Extension types (comma-separated, default all)")
    .action(async (accountId: string, opts) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const id = normalizeId(accountId);
        const data = await callApi({
          creds,
          service: "campaign",
          path: "AdExtensionsAssociations/Query",
          accountId: id,
          body: {
            AccountId: id,
            AdExtensionType: opts.type ? commaList(opts.type).join(",") : ALL_EXTENSION_TYPES,
            AssociationType: opts.entity,
            EntityIds: commaList(opts.ids),
          },
        });
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("conversion-goals <account-id>")
    .description("List conversion goals")
    .option("--type <type>", "Goal types (comma-separated): Url, Duration, PagesViewedPerVisit, Event, AppInstall, OfflineConversion, InStoreTransaction (default all)")
    .option("--tag-ids <ids>", "Filter by UET tag IDs (comma-separated)")
    .action(async (accountId: string, opts) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const id = normalizeId(accountId);
        const types = opts.type ? commaList(opts.type).join(",") : ALL_GOAL_TYPES;
        const data = opts.tagIds
          ? await callApi({
              creds,
              service: "campaign",
              path: "ConversionGoals/QueryByTagIds",
              accountId: id,
              body: {
                TagIds: commaList(opts.tagIds),
                ConversionGoalTypes: types,
              },
            })
          : await callApi({
              creds,
              service: "campaign",
              path: "ConversionGoals/QueryByIds",
              accountId: id,
              body: {
                ConversionGoalIds: null,
                ConversionGoalTypes: types,
              },
            });
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("uet-tags <account-id>")
    .description("List UET (Universal Event Tracking) tags")
    .action(async (accountId: string) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const data = await callApi({
          creds,
          service: "campaign",
          path: "UetTags/QueryByIds",
          accountId: normalizeId(accountId),
          body: { TagIds: null },
        });
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("labels <account-id>")
    .description("List labels for the account")
    .action(async (accountId: string) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const data = await callApi({
          creds,
          service: "campaign",
          path: "Labels/QueryByIds",
          accountId: normalizeId(accountId),
          body: { LabelIds: null },
        });
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });
}
