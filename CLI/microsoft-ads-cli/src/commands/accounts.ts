import { Command } from "commander";
import { loadCredentials } from "../auth.js";
import { callApi } from "../api.js";
import { output, fatal, normalizeId } from "../utils.js";

export function registerAccountCommands(program: Command): void {
  program
    .command("accounts")
    .description("List accessible ad accounts")
    .option("--page-index <n>", "Page index (0-based)", "0")
    .option("--page-size <n>", "Results per page", "100")
    .option("--all-statuses", "Include Draft, Inactive, and Pending accounts (default: Active + Pause only)")
    .action(async (opts) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        // SearchAccounts only supports Equals on AccountLifeCycleStatus, so we
        // scope by the authenticated user and filter statuses client-side.
        const userData = (await callApi({
          creds,
          service: "customer",
          path: "User/Query",
          body: { UserId: null },
        })) as { User?: { Id?: string | number } };
        const userId = userData.User?.Id;
        if (!userId) throw new Error("Could not resolve the authenticated user's ID");

        const data = (await callApi({
          creds,
          service: "customer",
          path: "Accounts/Search",
          body: {
            PageInfo: {
              Index: parseInt(opts.pageIndex),
              Size: parseInt(opts.pageSize),
            },
            Predicates: [{ Field: "UserId", Operator: "Equals", Value: String(userId) }],
          },
        })) as { Accounts?: Array<{ AccountLifeCycleStatus?: string }> };

        if (!opts.allStatuses && Array.isArray(data.Accounts)) {
          data.Accounts = data.Accounts.filter((a) =>
            a.AccountLifeCycleStatus === "Active" || a.AccountLifeCycleStatus === "Pause"
          );
        }
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("account <account-id>")
    .description("Get a specific ad account")
    .action(async (accountId: string) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const data = await callApi({
          creds,
          service: "customer",
          path: "Account/Query",
          body: { AccountId: normalizeId(accountId) },
        });
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("account-hierarchy [customer-id]")
    .description("List advertiser accounts under a manager account (customer)")
    .option("--only-parent-accounts", "Exclude linked accounts under other customers")
    .action(async (customerId: string | undefined, opts) => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const id = customerId ? normalizeId(customerId) : creds.customer_id ?? null;
        const data = await callApi({
          creds,
          service: "customer",
          path: "AccountsInfo/Query",
          customerId: id ?? undefined,
          body: {
            CustomerId: id,
            OnlyParentAccounts: !!opts.onlyParentAccounts,
          },
        });
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });

  program
    .command("user")
    .description("Get the current authenticated user info")
    .action(async () => {
      try {
        const creds = await loadCredentials(program.opts().credentials);
        const data = await callApi({
          creds,
          service: "customer",
          path: "User/Query",
          body: { UserId: null },
        });
        output(data, program.opts().format);
      } catch (err) {
        fatal((err as Error).message);
      }
    });
}
