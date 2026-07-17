import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { homedir } from "node:os";

export interface Credentials {
  access_token: string;
  developer_token: string;
  customer_id?: string;
  account_id?: string;
  client_id?: string;
  client_secret?: string;
  refresh_token?: string;
  token_expiry?: string;
  tenant?: string;
  identity_provider?: string;
}

export function isGoogleIdentity(creds: Pick<Credentials, "identity_provider">): boolean {
  return (creds.identity_provider || "").toLowerCase() === "google";
}

export const DEFAULT_PATH = join(
  homedir(),
  ".config",
  "microsoft-ads-cli",
  "credentials.json"
);

export function tokenEndpoint(tenant?: string): string {
  return `https://login.microsoftonline.com/${tenant || "common"}/oauth2/v2.0/token`;
}

export const OAUTH_SCOPE = "https://ads.microsoft.com/msads.manage offline_access";

// Google-federated Microsoft Advertising users (e.g. Google Workspace sign-in)
// authenticate with a Google OAuth token; the token only proves identity —
// Microsoft enforces its own authorization via the IdentityProvider header.
export const GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth";
export const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
export const GOOGLE_SCOPE = "openid email profile";

export function saveCredentials(path: string, creds: Credentials): void {
  const dir = dirname(path);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  writeFileSync(path, JSON.stringify(creds, null, 2) + "\n", { encoding: "utf-8", mode: 0o600 });
}

function isTokenExpired(creds: Credentials): boolean {
  if (!creds.access_token || !creds.token_expiry) return true;
  return Date.now() >= new Date(creds.token_expiry).getTime() - 60_000;
}

async function refreshAccessToken(creds: Credentials): Promise<{ access_token: string; refresh_token?: string; token_expiry: string }> {
  const google = isGoogleIdentity(creds);
  const params = new URLSearchParams({
    client_id: creds.client_id!,
    refresh_token: creds.refresh_token!,
    grant_type: "refresh_token",
    ...(google ? {} : { scope: OAUTH_SCOPE }),
  });
  if (creds.client_secret) params.set("client_secret", creds.client_secret);

  const res = await fetch(google ? GOOGLE_TOKEN_URL : tokenEndpoint(creds.tenant), {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: params,
  });

  const data = await res.json() as Record<string, unknown>;
  if (!res.ok) {
    const msg = (data.error_description || data.error || `HTTP ${res.status}`) as string;
    throw new Error(`Token refresh failed: ${msg}`);
  }

  return {
    access_token: data.access_token as string,
    refresh_token: data.refresh_token as string | undefined,
    token_expiry: new Date(Date.now() + (data.expires_in as number) * 1000).toISOString(),
  };
}

function canRefresh(creds: Credentials): boolean {
  return !!(creds.refresh_token && creds.client_id);
}

export async function loadCredentials(path?: string): Promise<Credentials> {
  let creds: Credentials;
  let sourcePath: string | undefined;

  if (path) {
    creds = JSON.parse(readFileSync(path, "utf-8"));
    sourcePath = path;
  } else {
    const accessToken = process.env.MICROSOFT_ADS_ACCESS_TOKEN;
    const developerToken = process.env.MICROSOFT_ADS_DEVELOPER_TOKEN;
    if (accessToken && developerToken) {
      return {
        access_token: accessToken,
        developer_token: developerToken,
        customer_id: process.env.MICROSOFT_ADS_CUSTOMER_ID,
        account_id: process.env.MICROSOFT_ADS_ACCOUNT_ID,
        identity_provider: process.env.MICROSOFT_ADS_IDENTITY_PROVIDER,
      };
    }

    if (existsSync(DEFAULT_PATH)) {
      creds = JSON.parse(readFileSync(DEFAULT_PATH, "utf-8"));
      sourcePath = DEFAULT_PATH;
    } else {
      throw new Error(
        `No credentials found. Provide one of:\n` +
        `  1. "microsoft-ads-cli auth login" to set up OAuth\n` +
        `  2. --credentials <path> flag\n` +
        `  3. MICROSOFT_ADS_ACCESS_TOKEN and MICROSOFT_ADS_DEVELOPER_TOKEN env vars\n` +
        `  4. ${DEFAULT_PATH}`
      );
    }
  }

  if (canRefresh(creds) && isTokenExpired(creds)) {
    const refreshed = await refreshAccessToken(creds);
    creds.access_token = refreshed.access_token;
    if (refreshed.refresh_token) creds.refresh_token = refreshed.refresh_token;
    creds.token_expiry = refreshed.token_expiry;
    if (sourcePath) {
      saveCredentials(sourcePath, creds);
    }
  }

  if (!creds.access_token || !creds.developer_token) {
    throw new Error(
      `Credentials file is missing required fields. Run "microsoft-ads-cli auth login" to set up.`
    );
  }

  return creds;
}
