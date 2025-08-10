// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { MSLLMClient } from "../../utils/ms-llm.ts";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  ImportFromUrlResponse,
  RestResponse,
} from "../../dto/controller-response.ts";
import { getAuthenticatedUserOrThrow } from "../../utils/auth.ts";

Deno.serve(async (req) => {
  try {
    const { url } = await req.json();
    // Sanitize the URL to remove unecessary parameters
    const sanitizedUrl = await sanitizeUrl(url);
    const supabase = createSupabaseAdminClient();

    // If we are not in DEV mode, we need to authenticate the user
    let userId: string | null = null;
    if (!shouldBypassAuth()) {
      try {
        userId = await getAuthenticatedUserIdOrThrow(supabase, req);
      } catch (authErr) {
        const message = authErr instanceof Error
          ? authErr.message
          : "Unauthorized";
        return jsonError(message, 401);
      }
    }

    // Check if the content already exists in the database
    // To avoid duplicates, we should only import the content once.
    const existingContent = await findExistingContent(supabase, sanitizedUrl);
    if (existingContent) {
      console.log("✅ Existing content found:", existingContent);
      const mealContent: ImportFromUrlResponse = {
        content: existingContent.content,
        metadata: existingContent.metadata,
      };
      const restResponse: RestResponse<ImportFromUrlResponse> = {
        success: true,
        error: null,
        error_code: null,
        data: mealContent,
      };
      return jsonOk(restResponse);
    }

    // If the content does not exist in the DB, we need to extract the content from the URL
    const extractionResponse = await extractContent(sanitizedUrl);
    if (!extractionResponse.success) {
      return jsonOk(extractionResponse);
    }

    // Insert the content into the DB
    const { importedContent, error: insertError } = await insertImportedContent(
      supabase,
      userId,
      sanitizedUrl,
      extractionResponse,
    );
    if (insertError) {
      console.error("Error inserting content:", insertError);
      return jsonError("Failed to store content", 500);
    }

    // Increment the user's AI imports used counter
    await incrementAiImportsUsedIfNeeded(supabase, userId);

    // Return the content
    const responseContent: ImportFromUrlResponse = {
      content: importedContent.content,
      metadata: importedContent.metadata,
    };
    const restResponse: RestResponse<ImportFromUrlResponse> = {
      success: true,
      error: null,
      error_code: null,
      data: responseContent,
    };
    return jsonOk(restResponse);
  } catch (error) {
    console.error("Error in import-from-url function:", error);
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
  return user.id;
}

async function findExistingContent(
  supabase: SupabaseClient,
  sourceUrl: string,
) {
  const { data } = await supabase
    .from("imported_content")
    .select("*")
    .eq("source_url", sourceUrl)
    .order("created_at", { ascending: false })
    .limit(1)
    .single();
  return data;
}

async function extractContent(sanitizedUrl: string) {
  const msLLM = new MSLLMClient();
  return await msLLM.callAPI("/extract-content", { url: sanitizedUrl }, "POST");
}

async function insertImportedContent(
  supabase: SupabaseClient,
  userId: string | null,
  sourceUrl: string,
  response: RestResponse<ImportFromUrlResponse>,
) {
  const { data, error } = await supabase
    .from("imported_content")
    .insert({
      user_id: userId,
      source_url: sourceUrl,
      content: response.data?.content || null,
      metadata: response.data?.metadata || null,
    })
    .select()
    .single();
  return { importedContent: data, error };
}

async function incrementAiImportsUsedIfNeeded(
  supabase: SupabaseClient,
  userId: string | null,
) {
  if (!userId) return;
  const { error } = await supabase.rpc("increment_ai_imports_used", {
    user_id: userId,
  });
  if (error) {
    console.error("Error updating user profile:", error);
  }
}

function jsonOk<T>(data: T): Response {
  return new Response(JSON.stringify(data), {
    headers: { "Content-Type": "application/json" },
  });
}

function jsonError(
  message: string,
  status = 500,
  error_code: string | null = null,
): Response {
  const body: RestResponse<ImportFromUrlResponse> = {
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

const sanitizeUrl = async (url: string): Promise<string> => {
  // Resolve short links (vt.tiktok.com, vm.tiktok.com, ig.me, etc.)
  const res = await fetch(url, { redirect: "follow" });
  const finalUrl = res.url;

  let minimalUrl = null;

  // TikTok → prefer https://www.tiktok.com/@<username>/video/<video_id>
  if (finalUrl.includes("tiktok.com")) {
    // If username is present, preserve it
    const withUser = finalUrl.match(/\/@([^/]+)\/video\/(\d+)/);
    if (withUser) {
      minimalUrl = `https://www.tiktok.com/@${withUser[1]}/video/${
        withUser[2]
      }`;
    } else {
      // Try canonical tag to resolve username form
      const canonical = await getCanonicalFromHtml(finalUrl, "tiktok");
      if (canonical) {
        minimalUrl = canonical;
      } else {
        // Fallback: keep the original URL (without query) if username is missing
        const idOnly = finalUrl.match(/\/video\/(\d+)/);
        if (idOnly) {
          const u = new URL(finalUrl);
          u.search = "";
          minimalUrl = u.toString();
        }
      }
    }
  } // Instagram → keep only https://www.instagram.com/reel/<shortcode>/ (no username requirement)
  else if (finalUrl.includes("instagram.com")) {
    const match = finalUrl.match(/\/reel\/([A-Za-z0-9_-]+)/);
    if (match) {
      minimalUrl = `https://www.instagram.com/reel/${match[1]}/`;
    }
  }

  // if it's not tiktok or instagram, return the final URL
  if (!minimalUrl) {
    // Remove the query params from the final URL
    const urlObj = new URL(finalUrl);
    urlObj.search = "";
    minimalUrl = urlObj.toString();
    return minimalUrl;
  }

  return minimalUrl;
};

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
