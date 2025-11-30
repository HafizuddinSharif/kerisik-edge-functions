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
    console.log("[IMPORT URL] Importing recipe from URL (edge proxy)");
    const { url, email } = await req.json();
    console.log("[IMPORT URL] Email:", email);

    // Authenticate user via Supabase (read-only, no DB writes)
    const supabase = createSupabaseAdminClient();
    if (!shouldBypassAuth()) {
      try {
        await getAuthenticatedUserIdOrThrow(supabase, req);
      } catch (authErr) {
        const message = authErr instanceof Error
          ? authErr.message
          : "Unauthorized";
        return jsonError(message, 401);
      }
    }

    // Sanitize the URL to remove unnecessary parameters / resolve redirects
    let resolved = url;
    if (!checkIfUrlIsAllowed(url)) {
      console.log("[IMPORT URL] URL is not youtube or tiktok:", url);
      resolved = await resolveToFinalUrl(url);
    }
    const sanitizedUrl = await sanitizeUrl(resolved);
    console.log("[IMPORT URL] URL:", url);
    console.log("[IMPORT URL] Sanitized URL:", sanitizedUrl);

    // Proxy call to FastAPI backend which owns imported_content writes
    const backendBaseUrl = Deno.env.get("MS_LLM_BASE_URL") ??
      "http://host.docker.internal:8000";
    const backendUrl = `${backendBaseUrl}/api/v2/import-from-url`;

    const headers: Record<string, string> = {
      "Content-Type": "application/json",
    };
    const apiKey = Deno.env.get("MS_LLM_API_KEY");
    if (apiKey) {
      headers["x-api-key"] = apiKey;
    }

    const backendResponse = await fetch(backendUrl, {
      method: "POST",
      headers,
      body: JSON.stringify({
        url: sanitizedUrl,
        email,
        mode: "async",
      }),
    });

    const body = await backendResponse.text();

    return new Response(body, {
      status: backendResponse.status,
      headers: {
        "Content-Type":
          backendResponse.headers.get("Content-Type") ??
          "application/json",
      },
    });
  } catch (error) {
    console.error("[IMPORT URL] Error in import-from-url edge proxy:", error);
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
  const envValue =
    (Deno.env.get("NODE_ENV") || Deno.env.get("ENVIRONMENT") || "")
      .toLowerCase();
  return envValue === "development";
}

function shouldBypassAuth(): boolean {
  return isDevelopment() && getBooleanEnv("IMPORT_RECIPE_NO_AUTH", false);
}

function createSupabaseAdminClient(): SupabaseClient {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  return createClient(supabaseUrl, supabaseServiceKey);
}

async function getAuthenticatedUserIdOrThrow(
  supabase: SupabaseClient,
  req: Request,
): Promise<string> {
  const user = await getAuthenticatedUserOrThrow(supabase, req);
  const { data: profile, error } = await supabase
    .from("user_profile")
    .select("id")
    .eq("auth_id", user.id)
    .single();

  if (error || !profile) {
    console.error("User profile not found for auth user", {
      authUserId: user.id,
      error,
    });
    throw new Error("User profile not found");
  }

  return profile.id as string;
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

function jsonError(
  message: string,
  status = 500,
  error_code: string | null = null,
): Response {
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

const checkIfUrlIsAllowed = (url: string): boolean => {
  return url.includes("tiktok.com") || url.includes("instagram.com") ||
    url.includes("youtube.com") || url.includes("youtu.be");
};

const resolveToFinalUrl = async (url: string): Promise<string> => {
  const res = await fetch(url, { redirect: "follow" });
  return res.url;
};

const sanitizeUrl = async (url: string): Promise<string> => {
  // Resolve short links (vt.tiktok.com, vm.tiktok.com, ig.me, etc.)
  console.log("[IMPORT URL] Final URL:", url);

  let minimalUrl = null;

  // TikTok → prefer https://www.tiktok.com/@<username>/video/<video_id>
  if (url.includes("tiktok.com")) {
    // If username is present, preserve it
    const withUser = url.match(/\/@([^/]+)\/video\/(\d+)/);
    if (withUser) {
      minimalUrl = `https://www.tiktok.com/@${withUser[1]}/video/${
        withUser[2]
      }`;
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

  console.log("[IMPORT URL] Minimal URL:", minimalUrl);

  return minimalUrl;
};

async function findUserProfileByEmail(supabase: SupabaseClient, email: string) {
  const { data, error } = await supabase
    .from("user_profile")
    .select("*")
    .eq("email", email)
    .single();
  return data;
}

async function getCanonicalFromHtml(
  pageUrl: string,
  platform: "tiktok",
): Promise<string | null> {
  try {
    const resp = await fetch(pageUrl, {
      redirect: "follow",
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
        "Accept":
          "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      },
    });
    const html = await resp.text();
    if (platform === "tiktok") {
      const m = html.match(
        /<link[^>]+rel=["']canonical["'][^>]+href=["'](https?:\/\/www\.tiktok\.com\/@[^"']+?\/video\/\d+)["']/i,
      );
      if (m) {
        const u = new URL(m[1]);
        u.search = "";
        return u.toString();
      }
    }
  } catch (_err) {
    // ignore parsing/network errors; caller will fallback
  }
  return null;
}
