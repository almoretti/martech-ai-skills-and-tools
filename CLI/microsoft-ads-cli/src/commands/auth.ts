import { Command } from "commander";
import { createServer } from "node:http";
import { exec } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import {
  DEFAULT_PATH,
  saveCredentials,
  tokenEndpoint,
  OAUTH_SCOPE,
  GOOGLE_AUTH_URL,
  GOOGLE_TOKEN_URL,
  GOOGLE_SCOPE,
} from "../auth.js";
import type { Credentials } from "../auth.js";
import { fatal } from "../utils.js";

function openBrowser(url: string): void {
  const cmd =
    process.platform === "darwin"
      ? `open "${url}"`
      : process.platform === "win32"
        ? `start "" "${url}"`
        : `xdg-open "${url}"`;
  exec(cmd, () => {});
}

export function registerAuthCommands(program: Command): void {
  const auth = program.command("auth").description("Authentication commands");

  auth
    .command("login")
    .description("Authorize with Microsoft (or Google, for Google-federated accounts) and save OAuth2 credentials")
    .option("--developer-token <token>", "Microsoft Advertising developer token")
    .option("--client-id <id>", "OAuth client ID (Microsoft Entra app, or Google OAuth client with --identity-provider google)")
    .option("--client-secret <secret>", "Client secret (web app registrations; required for Google desktop clients)")
    .option(
      "--identity-provider <provider>",
      "Identity provider: microsoft or google. Use google if you sign in to Microsoft Advertising with a Google account",
      "microsoft"
    )
    .option("--tenant <tenant>", "Entra ID tenant (default: common)", "common")
    .option("--customer-id <id>", "Default manager account (customer) ID to save")
    .option("--account-id <id>", "Default ad account ID to save")
    .option("--port <port>", "Local server port (0 = auto)", "0")
    .option("--no-browser", "Print auth URL instead of opening browser")
    .action(async (opts) => {
      try {
        const credsPath = program.opts().credentials || DEFAULT_PATH;

        let existing: Partial<Credentials> = {};
        if (existsSync(credsPath)) {
          try {
            existing = JSON.parse(readFileSync(credsPath, "utf-8"));
          } catch {}
        }

        const developerToken = opts.developerToken || existing.developer_token;
        const clientId = opts.clientId || existing.client_id;
        const clientSecret = opts.clientSecret || existing.client_secret;
        const tenant = opts.tenant || existing.tenant || "common";
        const provider = (opts.identityProvider || existing.identity_provider || "microsoft").toLowerCase();

        if (provider !== "microsoft" && provider !== "google") {
          fatal(`Invalid --identity-provider "${provider}". Use "microsoft" or "google".`);
        }

        if (!developerToken || !clientId || (provider === "google" && !clientSecret)) {
          const missing: string[] = [];
          if (!developerToken) missing.push("--developer-token");
          if (!clientId) missing.push("--client-id");
          if (provider === "google" && !clientSecret) missing.push("--client-secret (required for Google OAuth clients)");
          fatal(
            `Missing required credentials: ${missing.join(", ")}.\n` +
            `Provide them as flags or in ${credsPath}`
          );
        }

        const tokens = await authorize(clientId, clientSecret, tenant, provider, {
          port: parseInt(opts.port),
          openBrowserFn: opts.browser ? openBrowser : undefined,
        });

        const creds: Credentials = {
          ...existing,
          developer_token: developerToken,
          client_id: clientId,
          ...(clientSecret ? { client_secret: clientSecret } : {}),
          identity_provider: provider,
          tenant,
          ...(opts.customerId ? { customer_id: opts.customerId } : {}),
          ...(opts.accountId ? { account_id: opts.accountId } : {}),
          access_token: tokens.access_token,
          refresh_token: tokens.refresh_token,
          token_expiry: tokens.token_expiry,
        } as Credentials;

        saveCredentials(credsPath, creds);
        process.stderr.write(`Credentials saved to ${credsPath}\n`);
      } catch (err) {
        fatal((err as Error).message);
      }
    });
}

interface AuthorizeOptions {
  port: number;
  openBrowserFn?: (url: string) => void;
}

interface TokenResult {
  access_token: string;
  refresh_token: string;
  token_expiry: string;
}

function escapeHtml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

async function authorize(
  clientId: string,
  clientSecret: string | undefined,
  tenant: string,
  provider: string,
  opts: AuthorizeOptions,
): Promise<TokenResult> {
  const google = provider === "google";
  return new Promise<TokenResult>((resolve, reject) => {
    let done = false;
    let timer: ReturnType<typeof setTimeout>;

    function finish(fn: () => void) {
      if (done) return;
      done = true;
      clearTimeout(timer);
      server.close(() => {});
      fn();
    }

    const server = createServer(async (req, res) => {
      const url = new URL(req.url!, `http://localhost`);

      if (!url.searchParams.has("code") && !url.searchParams.has("error")) {
        res.writeHead(404);
        res.end();
        return;
      }

      try {
        const error = url.searchParams.get("error");
        if (error) {
          const desc = url.searchParams.get("error_description") || "";
          res.writeHead(200, { "Content-Type": "text/html" });
          res.end(`<html><body><h2>Authorization denied.</h2><p>${escapeHtml(desc)}</p><p>You can close this tab.</p></body></html>`);
          finish(() => reject(new Error(`Authorization denied: ${error} ${desc}`.trim())));
          return;
        }

        const code = url.searchParams.get("code")!;
        const port = (server.address() as { port: number }).port;
        const redirectUri = `http://localhost:${port}`;

        const params = new URLSearchParams({
          code,
          client_id: clientId,
          redirect_uri: redirectUri,
          grant_type: "authorization_code",
          ...(google ? {} : { scope: OAUTH_SCOPE }),
        });
        if (clientSecret) params.set("client_secret", clientSecret);

        const tokenRes = await fetch(google ? GOOGLE_TOKEN_URL : tokenEndpoint(tenant), {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: params,
        });

        const data = await tokenRes.json() as Record<string, unknown>;
        if (!tokenRes.ok) {
          const msg = (data.error_description || data.error || `HTTP ${tokenRes.status}`) as string;
          res.writeHead(200, { "Content-Type": "text/html" });
          res.end(`<html><body><h2>Token exchange failed.</h2><p>${escapeHtml(msg)}</p></body></html>`);
          finish(() => reject(new Error(`Token exchange failed: ${msg}`)));
          return;
        }

        res.writeHead(200, { "Content-Type": "text/html" });
        res.end("<html><body><h2>Authorization successful!</h2><p>You can close this tab.</p></body></html>");
        finish(() => resolve({
          access_token: data.access_token as string,
          refresh_token: data.refresh_token as string,
          token_expiry: new Date(Date.now() + (data.expires_in as number) * 1000).toISOString(),
        }));
      } catch (err) {
        try {
          res.writeHead(500, { "Content-Type": "text/plain" });
          res.end("Internal error");
        } catch {}
        finish(() => reject(err));
      }
    });

    server.listen(opts.port, "127.0.0.1", () => {
      const port = (server.address() as { port: number }).port;
      const redirectUri = `http://localhost:${port}`;
      const authUrl = google
        ? `${GOOGLE_AUTH_URL}` +
          `?client_id=${encodeURIComponent(clientId)}` +
          `&redirect_uri=${encodeURIComponent(redirectUri)}` +
          `&response_type=code` +
          `&scope=${encodeURIComponent(GOOGLE_SCOPE)}` +
          `&access_type=offline` +
          `&prompt=consent`
        : `https://login.microsoftonline.com/${encodeURIComponent(tenant)}/oauth2/v2.0/authorize` +
          `?client_id=${encodeURIComponent(clientId)}` +
          `&redirect_uri=${encodeURIComponent(redirectUri)}` +
          `&response_type=code` +
          `&response_mode=query` +
          `&scope=${encodeURIComponent(OAUTH_SCOPE)}` +
          `&prompt=select_account`;

      if (opts.openBrowserFn) {
        process.stderr.write(`Opening browser for authorization...\nIf it doesn't open, visit:\n${authUrl}\n`);
        opts.openBrowserFn(authUrl);
      } else {
        process.stderr.write(`Open this URL in your browser:\n${authUrl}\n`);
      }
    });

    timer = setTimeout(() => {
      finish(() => reject(new Error("Authorization timed out after 180 seconds")));
    }, 180_000);
  });
}
