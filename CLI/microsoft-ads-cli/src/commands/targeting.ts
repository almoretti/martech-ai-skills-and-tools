import { Command } from "commander";
import { loadCredentials } from "../auth.js";
import { callApi } from "../api.js";
import { output, fatal, normalizeId } from "../utils.js";

const ALL_AUDIENCE_TYPES =
  "Custom,InMarket,Product,RemarketingList,SimilarRemarketingList,CombinedList,CustomerList,ImpressionBasedRemarketingList";

export function registerTargetingCommands(program: Command): void {
  program
    .command("keywords <account-id> <ad-group-id>")
    .description("List keywords for an ad group")
    .action(async (accountId: string, adGroupId: string) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const data = await callApi({
          creds,
          service: "campaign",
          path: "Keywords/QueryByAdGroupId",
          accountId: normalizeId(accountId),
          // ReturnAdditionalFields "ImpressionTrackingUrls" is rejected by the
          // v13 REST endpoint ("The request message is null").
          body: {
            AdGroupId: adGroupId,
          },
        });
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("audiences <account-id>")
    .description("List audience segments")
    .option("--type <type>", "Audience types (comma-separated): Custom, InMarket, Product, RemarketingList, SimilarRemarketingList, CustomerList, CombinedList (default all)")
    .action(async (accountId: string, opts) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const types = opts.type
          ? opts.type.split(",").map((t: string) => t.trim()).join(",")
          : ALL_AUDIENCE_TYPES;
        const data = await callApi({
          creds,
          service: "campaign",
          path: "Audiences/QueryByIds",
          accountId: normalizeId(accountId),
          body: {
            AudienceIds: null,
            Type: types,
          },
        });
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("user-lists <account-id>")
    .description("List remarketing lists")
    .action(async (accountId: string) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const data = await callApi({
          creds,
          service: "campaign",
          path: "Audiences/QueryByIds",
          accountId: normalizeId(accountId),
          body: {
            AudienceIds: null,
            Type: "RemarketingList,SimilarRemarketingList,CustomerList",
          },
        });
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("negative-keywords <account-id>")
    .description("List shared negative keyword lists, or entity-level negative keywords with --campaign/--ad-group")
    .option("--campaign <id>", "Get negative keywords attached to this campaign")
    .option("--ad-group <id>", "Get negative keywords attached to this ad group")
    .action(async (accountId: string, opts) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const id = normalizeId(accountId);
        if (opts.campaign || opts.adGroup) {
          const data = await callApi({
            creds,
            service: "campaign",
            path: "NegativeKeywords/QueryByEntityIds",
            accountId: id,
            body: {
              EntityIds: [opts.campaign || opts.adGroup],
              EntityType: opts.campaign ? "Campaign" : "AdGroup",
            },
          });
          output(data, program.opts().format);
          return;
        }
        const data = await callApi({
          creds,
          service: "campaign",
          path: "SharedEntities/QueryByAccountId",
          accountId: id,
          body: { SharedEntityType: "NegativeKeywordList" },
        });
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("negative-keyword-items <account-id> <list-id>")
    .description("List the negative keywords in a shared negative keyword list")
    .action(async (accountId: string, listId: string) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const data = await callApi({
          creds,
          service: "campaign",
          path: "ListItems/QueryBySharedList",
          accountId: normalizeId(accountId),
          body: {
            SharedList: { Id: listId, Type: "NegativeKeywordList" },
            SharedEntityScope: "Account",
          },
        });
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });
}
