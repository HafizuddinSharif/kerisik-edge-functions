// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { getAuthenticatedUserOrThrow } from "../utils/auth.ts";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/**
 * Thin proxy edge function:
 *  - Validates the Supabase auth token (unless in DEV bypass mode)
 *  - Normalises/sanitises the incoming URL
 *  - Forwards the request to the FastAPI backend `/api/v2/import-from-url`
 *    which owns ALL Supabase writes for imported_content.
 *
 * This function MUST NOT perform any inserts/updates/RPC calls to Supabase.
 */
Deno.serve(async (req) => {
  const requestId = crypto.randomUUID();
  const logPrefix = `[IMPORT URL][${requestId}]`;
  try {
    console.log(`${logPrefix} ===== START: Importing recipe from URL (edge proxy) =====`);
    console.log(`${logPrefix} Request method:`, req.method);
    console.log(`${logPrefix} Request URL:`, req.url);

    const { url, email, notification_device_id } = await req.json();
    console.log(`${logPrefix} Received URL:`, url);
    console.log(`${logPrefix} Received email:`, maskEmail(email));

    // Authenticate user via Supabase (read-only, no DB writes)
    console.log(`${logPrefix} Creating Supabase admin client...`);
    const supabase = createSupabaseAdminClient();
    console.log(`${logPrefix} Supabase admin client created`);

    const bypassAuth = shouldBypassAuth();
    console.log(`${logPrefix} Auth bypass check:`, bypassAuth);

    if (!bypassAuth) {
      console.log(`${logPrefix} Authenticating user...`);
      try {
        const userId = await getAuthenticatedUserIdOrThrow(supabase, req, requestId);
        console.log(`${logPrefix} Authentication successful, user_profile ID:`, userId);
      } catch (authErr) {
        console.error(`${logPrefix} Authentication failed:`, authErr);
        const message = authErr instanceof Error ? authErr.message : "Unauthorized";
        return jsonError(message, 401, null, requestId);
      }
    } else {
      console.log(`${logPrefix} Auth bypassed (DEV mode)`);
    }

    // Sanitize the URL to remove unnecessary parameters / resolve redirects
    console.log(`${logPrefix} Starting URL sanitization...`);
    const redirectUrl = normalizeTikTokShortUrlForRedirect(url);
    console.log(`${logPrefix} Redirect URL candidate:`, redirectUrl);
    const shouldResolveRedirect = !isYouTubeUrl(redirectUrl);
    console.log(`${logPrefix} Should resolve redirects:`, shouldResolveRedirect);
    const resolved = shouldResolveRedirect ? await resolveToFinalUrl(redirectUrl) : redirectUrl;
    const sanitizedUrl = await sanitizeUrl(resolved);
    console.log(`${logPrefix} Original URL:`, url);
    console.log(`${logPrefix} Resolved URL:`, resolved);
    console.log(`${logPrefix} Sanitized URL:`, sanitizedUrl);

    // Proxy call to FastAPI backend which owns imported_content writes
    console.log(`${logPrefix} Preparing backend proxy call...`);
    const backendBaseUrl = Deno.env.get("MS_LLM_BASE_URL") ?? "http://host.docker.internal:8000";
    const backendUrl = `${backendBaseUrl}/api/v2/import-from-url`;
    console.log(`${logPrefix} Backend base URL:`, backendBaseUrl);
    console.log(`${logPrefix} Backend URL:`, backendUrl);

    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      "X-Request-ID": requestId,
    };
    const apiKey = Deno.env.get("MS_LLM_API_KEY");
    if (apiKey) {
      headers["x-api-key"] = apiKey;
      console.log(`${logPrefix} API key found, added to headers`);
    } else {
      console.log(`${logPrefix} No API key found in environment`);
    }

    const requestBody = {
      url: sanitizedUrl,
      email,
      mode: "async",
      request_id: requestId,
      notification_device_id: notification_device_id ?? null,
    };
    console.log(`${logPrefix} Backend request summary:`, {
      url: requestBody.url,
      mode: requestBody.mode,
      emailPresent: !!email,
      email: maskEmail(email),
    });

    console.log(`${logPrefix} Calling backend with retry logic...`);
    const backendResponse = await fetchWithRetry(backendUrl, {
      method: "POST",
      headers,
      body: JSON.stringify(requestBody),
    }, requestId);


    const body = await backendResponse.text();
    console.log(`${logPrefix} Backend response summary:`, summarizeBackendResponse(body));
    console.log(`${logPrefix} Backend response status:`, backendResponse.status);
    console.log(`${logPrefix} Backend response content-type:`, backendResponse.headers.get("Content-Type"));

    console.log(`${logPrefix} ===== END: Returning response to client =====`);
    return new Response(body, {
      status: backendResponse.status,
      headers: {
        "Content-Type": backendResponse.headers.get("Content-Type") ?? "application/json",
        "X-Request-ID": requestId,
      },
    });
  } catch (error) {
    console.error(`${logPrefix} ===== ERROR: Exception caught in main handler =====`);
    console.error(`${logPrefix} Error type:`, error?.constructor?.name);
    console.error(`${logPrefix} Error message:`, error instanceof Error ? error.message : String(error));
    console.error(`${logPrefix} Error stack:`, error instanceof Error ? error.stack : "No stack trace");
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonError(message, 500, null, requestId);
  }
});

// ------------------------------------------------------------------------------
// HELPER FUNCTIONS
// ------------------------------------------------------------------------------

function getBooleanEnv(name: string, defaultValue = false): boolean {
  const raw = (Deno.env.get(name) || "").toLowerCase();
  if (!raw) return defaultValue;
  return raw === "true" || raw === "1" || raw === "yes";
}

function isDevelopment(): boolean {
  const envValue = (Deno.env.get("NODE_ENV") || Deno.env.get("ENVIRONMENT") || "").toLowerCase();
  return envValue === "development";
}

function shouldBypassAuth(): boolean {
  const isDev = isDevelopment();
  const noAuth = getBooleanEnv("IMPORT_RECIPE_NO_AUTH", false);
  const result = isDev && noAuth;
  console.log("[IMPORT URL] shouldBypassAuth check:", { isDev, noAuth, result });
  return result;
}

function createSupabaseAdminClient(): SupabaseClient {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  console.log("[IMPORT URL] Creating Supabase client with URL:", supabaseUrl ? `${supabaseUrl.substring(0, 20)}...` : "MISSING");
  console.log("[IMPORT URL] Service key present:", !!supabaseServiceKey);
  if (!supabaseUrl || !supabaseServiceKey) {
    console.error("[IMPORT URL] Missing Supabase environment variables!");
  }
  return createClient(supabaseUrl, supabaseServiceKey);
}

async function getAuthenticatedUserIdOrThrow(supabase: SupabaseClient, req: Request, requestId: string): Promise<string> {
  const logPrefix = `[IMPORT URL][${requestId}]`;
  console.log(`${logPrefix} getAuthenticatedUserIdOrThrow: Starting authentication...`);
  const user = await getAuthenticatedUserOrThrow(supabase, req);
  console.log(`${logPrefix} getAuthenticatedUserIdOrThrow: Auth user ID:`, user.id);

  console.log(`${logPrefix} getAuthenticatedUserIdOrThrow: Querying user_profile by auth_id...`);
  const { data: profile, error } = await supabase.from("user_profile").select("id").eq("auth_id", user.id).single();

  if (error || !profile) {
    console.error(`${logPrefix} getAuthenticatedUserIdOrThrow: User profile not found`, {
      authUserId: user.id,
      error: error?.message || error,
      errorCode: error?.code,
      profileFound: !!profile,
    });
    throw new Error("User profile not found");
  }

  console.log(`${logPrefix} getAuthenticatedUserIdOrThrow: Profile found, ID:`, profile.id);
  return profile.id as string;
}

async function fetchWithRetry(url: string, init: RequestInit, requestId: string, maxAttempts = 3, baseDelayMs = 200): Promise<Response> {
  const logPrefix = `[IMPORT URL][${requestId}]`;
  console.log(`${logPrefix} fetchWithRetry: Starting fetch with retry logic`, {
    url,
    maxAttempts,
    baseDelayMs,
    method: init.method,
  });
  let lastError: unknown;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      console.log(`${logPrefix} fetchWithRetry: Making fetch request to ${url} (attempt ${attempt})`);
      const res = await fetch(url, init);
      console.log(`${logPrefix} fetchWithRetry: Response received, status: ${res.status}`);

      // If it's a success or a non-retryable error, return immediately
      const shouldRetry = shouldRetryResponse(res);
      console.log(`${logPrefix} fetchWithRetry: Should retry: ${shouldRetry}, is last attempt: ${attempt === maxAttempts}`);

      if (!shouldRetry || attempt === maxAttempts) {
        console.log(`${logPrefix} fetchWithRetry: Returning response (status: ${res.status})`);
        return res;
      }

      console.warn(`${logPrefix} fetchWithRetry: Backend responded with ${res.status}, retrying (${attempt}/${maxAttempts})`);
    } catch (err) {
      lastError = err;
      console.error(`${logPrefix} fetchWithRetry: Fetch error on attempt ${attempt}:`, err);

      if (attempt === maxAttempts) {
        console.error(`${logPrefix} fetchWithRetry: Failed to reach backend after all retries`);
        throw err;
      }

      console.warn(`${logPrefix} fetchWithRetry: Network error calling backend, retrying (${attempt}/${maxAttempts})`);
    }

    const delay = baseDelayMs * attempt;
    console.log(`${logPrefix} fetchWithRetry: Waiting ${delay}ms before next attempt...`);
    await new Promise((resolve) => setTimeout(resolve, delay));
  }

  console.error(`${logPrefix} fetchWithRetry: Exhausted all retries, throwing error`);
  throw lastError instanceof Error ? lastError : new Error("Unknown fetch error after retries");
}

function shouldRetryResponse(res: Response): boolean {
  // Retry on common transient upstream errors
  return res.status === 502 || res.status === 503 || res.status === 504;
}

function jsonOk<T>(data: T): Response {
  return new Response(JSON.stringify(data), {
    headers: { "Content-Type": "application/json" },
  });
}

function jsonAccepted<T>(data: T): Response {
  return new Response(JSON.stringify(data), {
    status: 202,
    headers: { "Content-Type": "application/json" },
  });
}

function jsonError(message: string, status = 500, error_code: string | null = null, request_id: string | null = null): Response {
  const body = {
    success: false,
    error: message,
    error_code,
    request_id,
    data: null,
  };
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...(request_id ? { "X-Request-ID": request_id } : {}),
    },
  });
}

function maskEmail(value: unknown): string | null {
  if (typeof value !== "string" || !value.trim()) return null;
  const [name, domain] = value.trim().split("@");
  if (!domain) return "***";
  const prefix = name ? `${name.slice(0, 2)}***` : "***";
  return `${prefix}@${domain}`;
}

function summarizeBackendResponse(body: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(body);
    return {
      success: parsed?.success,
      error: parsed?.error,
      error_code: parsed?.error_code,
      data_status: parsed?.data?.status,
      extract_id: parsed?.data?.extract_id,
      imported_content_id: parsed?.data?.imported_content_id,
      data_error_code: parsed?.data?.error_code,
      retry_count: parsed?.data?.retry_count,
      is_recipe_content: parsed?.data?.is_recipe_content,
    };
  } catch {
    return {
      raw_preview: body.slice(0, 500),
      raw_length: body.length,
    };
  }
}

const resolveToFinalUrl = async (url: string): Promise<string> => {
  try {
    const res = await fetch(url, { redirect: "follow" });
    return res.url;
  } catch (error) {
    throw error;
  }
};

function isYouTubeUrl(url: string): boolean {
  try {
    const host = new URL(url).hostname.toLowerCase();
    return (
      host === "youtube.com" ||
      host.endsWith(".youtube.com") ||
      host === "youtube-nocookie.com" ||
      host.endsWith(".youtube-nocookie.com") ||
      host === "youtu.be" ||
      host.endsWith(".youtu.be")
    );
  } catch {
    return false;
  }
}

const normalizeTikTokShortUrlForRedirect = (url: string): string => {
  try {
    const parsed = new URL(url);
    if (parsed.hostname.toLowerCase() !== "vt.tiktok.com") {
      return url;
    }

    parsed.pathname = parsed.pathname.replace(/\/+$/g, "");
    return parsed.toString();
  } catch {
    return url;
  }
};

const sanitizeUrl = async (url: string): Promise<string> => {

  let minimalUrl: string | null = null;

  // TikTok → prefer https://www.tiktok.com/@<username>/video/<video_id>
  if (url.includes("tiktok.com")) {
    // If username is present, preserve it
    const withUser = url.match(/\/@([^/]+)\/video\/(\d+)/);
    if (withUser) {
      minimalUrl = `https://www.tiktok.com/@${withUser[1]}/video/${withUser[2]}`;
    } else {
      // Try canonical tag to resolve username form
      const canonical = await getCanonicalFromHtml(url, "tiktok");
      if (canonical) {
        minimalUrl = canonical;
      } else {
        // Fallback: keep the original URL (without query) if username is missing
        const idOnly = url.match(/\/video\/(\d+)/);
        if (idOnly) {
          const u = new URL(url);
          u.search = "";
          minimalUrl = u.toString();
        }
      }
    }
  } // Instagram → keep only https://www.instagram.com/reel/<shortcode>/ (no username requirement)
  else if (url.includes("instagram.com")) {
    const match = url.match(/\/reel\/([A-Za-z0-9_-]+)/);
    if (match) {
      minimalUrl = `https://www.instagram.com/p/${match[1]}/`;
    }
  } else if (url.includes("youtube.com")) {
    const match = url.match(/\/watch\?v=([A-Za-z0-9_-]+)/);
    if (match) {
      minimalUrl = `https://www.youtube.com/watch?v=${match[1]}`;
    } else {
      const shortsMatch = url.match(/\/shorts\/([A-Za-z0-9_-]+)/);
      if (shortsMatch) {
        minimalUrl = `https://www.youtube.com/shorts/${shortsMatch[1]}`;
      }
    }
  } else if (url.includes("youtu.be")) {
    const match = url.match(/youtu\.be\/([A-Za-z0-9_-]+)/);
    if (match) {
      minimalUrl = `https://www.youtube.com/watch?v=${match[1]}`;
    }
  }

  // if it's not tiktok or instagram, return the final URL
  if (!minimalUrl) {
    // Remove the query params from the final URL
    const urlObj = new URL(url);
    urlObj.search = "";
    minimalUrl = urlObj.toString();
    return minimalUrl;
  }

  return minimalUrl;
};

async function findUserProfileByEmail(supabase: SupabaseClient, email: string) {
  const { data, error } = await supabase.from("user_profile").select("*").eq("email", email).single();
  return data;
}

async function getCanonicalFromHtml(pageUrl: string, platform: "tiktok"): Promise<string | null> {
  try {
    const resp = await fetch(pageUrl, {
      redirect: "follow",
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
        Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      },
    });
    const html = await resp.text();

    if (platform === "tiktok") {
      const m = html.match(/<link[^>]+rel=["']canonical["'][^>]+href=["'](https?:\/\/www\.tiktok\.com\/@[^"']+?\/video\/\d+)["']/i);
      if (m) {
        const u = new URL(m[1]);
        u.search = "";
        const canonicalUrl = u.toString();
        return canonicalUrl;
      }
    }
  } catch (err) {
    // ignore parsing/network errors; caller will fallback
  }
  return null;
}
