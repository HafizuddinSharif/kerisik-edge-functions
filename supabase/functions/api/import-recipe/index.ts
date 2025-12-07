// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { getAuthenticatedUserOrThrow } from "../../utils/auth.ts";
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
  try {
    console.log("[IMPORT URL] ===== START: Importing recipe from URL (edge proxy) =====");
    console.log("[IMPORT URL] Request method:", req.method);
    console.log("[IMPORT URL] Request URL:", req.url);

    const { url, email } = await req.json();
    console.log("[IMPORT URL] Received URL:", url);
    console.log("[IMPORT URL] Received email:", email);

    // Authenticate user via Supabase (read-only, no DB writes)
    console.log("[IMPORT URL] Creating Supabase admin client...");
    const supabase = createSupabaseAdminClient();
    console.log("[IMPORT URL] Supabase admin client created");

    const bypassAuth = shouldBypassAuth();
    console.log("[IMPORT URL] Auth bypass check:", bypassAuth);

    if (!bypassAuth) {
      console.log("[IMPORT URL] Authenticating user...");
      try {
        const userId = await getAuthenticatedUserIdOrThrow(supabase, req);
        console.log("[IMPORT URL] Authentication successful, user ID:", userId);
      } catch (authErr) {
        console.error("[IMPORT URL] Authentication failed:", authErr);
        const message = authErr instanceof Error ? authErr.message : "Unauthorized";
        return jsonError(message, 401);
      }
    } else {
      console.log("[IMPORT URL] Auth bypassed (DEV mode)");
    }

    // Sanitize the URL to remove unnecessary parameters / resolve redirects
    console.log("[IMPORT URL] Starting URL sanitization...");
    const resolved = await resolveToFinalUrl(url);
    const sanitizedUrl = await sanitizeUrl(resolved);
    console.log("[IMPORT URL] Original URL:", url);
    console.log("[IMPORT URL] Resolved URL:", resolved);
    console.log("[IMPORT URL] Sanitized URL:", sanitizedUrl);

    // Proxy call to FastAPI backend which owns imported_content writes
    console.log("[IMPORT URL] Preparing backend proxy call...");
    const backendBaseUrl = Deno.env.get("MS_LLM_BASE_URL") ?? "http://host.docker.internal:8000";
    const backendUrl = `${backendBaseUrl}/api/v2/import-from-url`;
    console.log("[IMPORT URL] Backend base URL:", backendBaseUrl);
    console.log("[IMPORT URL] Backend URL:", backendUrl);

    const headers: Record<string, string> = {
      "Content-Type": "application/json",
    };
    const apiKey = Deno.env.get("MS_LLM_API_KEY");
    if (apiKey) {
      headers["x-api-key"] = apiKey;
      console.log("[IMPORT URL] API key found, added to headers");
    } else {
      console.log("[IMPORT URL] No API key found in environment");
    }

    const requestBody = {
      url: sanitizedUrl,
      email,
      mode: "async",
    };
    console.log("[IMPORT URL] Request body:", JSON.stringify(requestBody));

    console.log("[IMPORT URL] Calling backend with retry logic...");
    const backendResponse = await fetchWithRetry(backendUrl, {
      method: "POST",
      headers,
      body: JSON.stringify(requestBody),
    });


    const body = await backendResponse.text();

    console.log("[IMPORT URL] ===== END: Returning response to client =====");
    return new Response(body, {
      status: backendResponse.status,
      headers: {
        "Content-Type": backendResponse.headers.get("Content-Type") ?? "application/json",
      },
    });
  } catch (error) {
    console.error("[IMPORT URL] ===== ERROR: Exception caught in main handler =====");
    console.error("[IMPORT URL] Error type:", error?.constructor?.name);
    console.error("[IMPORT URL] Error message:", error instanceof Error ? error.message : String(error));
    console.error("[IMPORT URL] Error stack:", error instanceof Error ? error.stack : "No stack trace");
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonError(message, 500);
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

async function getAuthenticatedUserIdOrThrow(supabase: SupabaseClient, req: Request): Promise<string> {
  console.log("[IMPORT URL] getAuthenticatedUserIdOrThrow: Starting authentication...");
  const user = await getAuthenticatedUserOrThrow(supabase, req);
  console.log("[IMPORT URL] getAuthenticatedUserIdOrThrow: Auth user ID:", user.id);

  console.log("[IMPORT URL] getAuthenticatedUserIdOrThrow: Querying user_profile...");
  const { data: profile, error } = await supabase.from("user_profile").select("id").eq("auth_id", user.id).single();

  if (error || !profile) {
    console.error("[IMPORT URL] getAuthenticatedUserIdOrThrow: User profile not found", {
      authUserId: user.id,
      error: error?.message || error,
      errorCode: error?.code,
      profileFound: !!profile,
    });
    throw new Error("User profile not found");
  }

  console.log("[IMPORT URL] getAuthenticatedUserIdOrThrow: Profile found, ID:", profile.id);
  return profile.id as string;
}

async function fetchWithRetry(url: string, init: RequestInit, maxAttempts = 3, baseDelayMs = 200): Promise<Response> {
  console.log("[IMPORT URL] fetchWithRetry: Starting fetch with retry logic", {
    url,
    maxAttempts,
    baseDelayMs,
    method: init.method,
  });
  let lastError: unknown;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      console.log(`[IMPORT URL] fetchWithRetry: Making fetch request to ${url}`);
      const res = await fetch(url, init);
      console.log(`[IMPORT URL] fetchWithRetry: Response received, status: ${res.status}`);

      // If it's a success or a non-retryable error, return immediately
      const shouldRetry = shouldRetryResponse(res);
      console.log(`[IMPORT URL] fetchWithRetry: Should retry: ${shouldRetry}, is last attempt: ${attempt === maxAttempts}`);

      if (!shouldRetry || attempt === maxAttempts) {
        console.log(`[IMPORT URL] fetchWithRetry: Returning response (status: ${res.status})`);
        return res;
      }

      console.warn(`[IMPORT URL] fetchWithRetry: Backend responded with ${res.status}, retrying (${attempt}/${maxAttempts})`);
    } catch (err) {
      lastError = err;
      console.error(`[IMPORT URL] fetchWithRetry: Fetch error on attempt ${attempt}:`, err);

      if (attempt === maxAttempts) {
        console.error("[IMPORT URL] fetchWithRetry: Failed to reach backend after all retries");
        throw err;
      }

      console.warn(`[IMPORT URL] fetchWithRetry: Network error calling backend, retrying (${attempt}/${maxAttempts})`);
    }

    const delay = baseDelayMs * attempt;
    console.log(`[IMPORT URL] fetchWithRetry: Waiting ${delay}ms before next attempt...`);
    await new Promise((resolve) => setTimeout(resolve, delay));
  }

  console.error("[IMPORT URL] fetchWithRetry: Exhausted all retries, throwing error");
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

function jsonError(message: string, status = 500, error_code: string | null = null): Response {
  const body = {
    success: false,
    error: message,
    error_code,
    data: null,
  };
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

const resolveToFinalUrl = async (url: string): Promise<string> => {
  try {
    const res = await fetch(url, { redirect: "follow" });
    return res.url;
  } catch (error) {
    throw error;
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
      minimalUrl = `https://www.instagram.com/reel/${match[1]}/`;
    }
  } else if (url.includes("youtube.com")) {
    const match = url.match(/\/watch\?v=([A-Za-z0-9_-]+)/);
    if (match) {
      minimalUrl = `https://www.youtube.com/watch?v=${match[1]}`;
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
