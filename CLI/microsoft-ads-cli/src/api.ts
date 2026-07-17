import { isGoogleIdentity, type Credentials } from "./auth.js";

export const BASE_URLS = {
  campaign: "https://campaign.api.bingads.microsoft.com/CampaignManagement/v13",
  customer: "https://clientcenter.api.bingads.microsoft.com/CustomerManagement/v13",
  reporting: "https://reporting.api.bingads.microsoft.com/Reporting/v13",
  adInsight: "https://adinsight.api.bingads.microsoft.com/Api/Advertiser/AdInsight/v13",
  bulk: "https://bulk.api.bingads.microsoft.com/Api/Advertiser/CampaignManagement/v13",
} as const;

export type ServiceName = keyof typeof BASE_URLS;

interface CallOptions {
  creds: Credentials;
  service: ServiceName;
  path: string;
  body?: Record<string, unknown>;
  accountId?: string;
  customerId?: string;
}

export async function callApi(opts: CallOptions): Promise<unknown> {
  const url = `${BASE_URLS[opts.service]}/${opts.path}`;
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Authorization: `Bearer ${opts.creds.access_token}`,
    DeveloperToken: opts.creds.developer_token,
  };
  // Google-federated users: tell Microsoft to validate the bearer token
  // against Google instead of Entra/MSA (else error 126 GoogleAccountIsRequired).
  if (isGoogleIdentity(opts.creds)) headers["IdentityProvider"] = "Google";

  const accountId = opts.accountId || opts.creds.account_id;
  const customerId = opts.customerId || opts.creds.customer_id;
  if (accountId) headers["CustomerAccountId"] = accountId;
  if (customerId) headers["CustomerId"] = customerId;

  const res = await fetch(url, {
    method: "POST",
    headers,
    body: JSON.stringify(opts.body || {}),
  });

  const text = await res.text();
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    data = { rawResponse: text };
  }

  if (!res.ok) {
    throw new Error(extractError(data, res.status));
  }

  return data;
}

function extractError(data: unknown, status: number): string {
  if (typeof data !== "object" || data === null) return `HTTP ${status}`;
  const err = data as Record<string, unknown>;
  // Campaign/Customer Management style: {Errors: [{Message, Code}]} or nested ApiFaultDetail
  const parts: string[] = [];
  const collect = (obj: unknown): void => {
    if (Array.isArray(obj)) {
      for (const item of obj) collect(item);
    } else if (typeof obj === "object" && obj !== null) {
      const o = obj as Record<string, unknown>;
      if (typeof o.Message === "string" && o.Message) parts.push(o.Message);
      for (const key of ["Errors", "OperationErrors", "BatchErrors", "Details"]) {
        if (o[key]) collect(o[key]);
      }
    }
  };
  collect(err);
  if (parts.length > 0) return parts.join("; ");
  if (typeof err.Message === "string") return err.Message;
  return `HTTP ${status}`;
}
