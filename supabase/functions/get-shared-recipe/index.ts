import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { RestResponse } from "../dto/controller-response.ts";

const SHARED_IMAGE_BUCKET = "shared-recipe-images";
const SIGNED_IMAGE_URL_TTL_SECONDS = 60 * 60;

interface SharedRecipeResponse {
  status: "active" | "expired" | "revoked" | "not_found";
  recipe: Record<string, unknown> | null;
  expiresAt: string | null;
  imageUrl: string | null;
}

interface SharedRecipeRow {
  id: string;
  recipe_payload: Record<string, unknown>;
  image_path: string | null;
  expires_at: string;
  revoked_at: string | null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders() });
  }

  if (req.method !== "GET") {
    return jsonError("Method not allowed", 405, "METHOD_NOT_ALLOWED");
  }

  try {
    const token = getTokenFromRequest(req);
    if (!token) {
      return jsonError("token is required", 400, "MISSING_TOKEN");
    }

    const supabase = createSupabaseAdminClient();
    const { data, error } = await supabase
      .from("shared_recipe_links")
      .select("id, recipe_payload, image_path, expires_at, revoked_at")
      .eq("token", token)
      .maybeSingle();

    if (error) {
      console.error("[GET SHARED RECIPE] Query failed:", error);
      return jsonError(
        "Failed to fetch shared recipe",
        500,
        "FETCH_SHARED_RECIPE_FAILED",
      );
    }

    if (!data) {
      return jsonSuccess<SharedRecipeResponse>({
        status: "not_found",
        recipe: null,
        expiresAt: null,
        imageUrl: null,
      });
    }

    const row = data as SharedRecipeRow;
    const now = Date.now();
    const expiresAtMs = Date.parse(row.expires_at);

    if (row.revoked_at) {
      return jsonSuccess<SharedRecipeResponse>({
        status: "revoked",
        recipe: null,
        expiresAt: row.expires_at,
        imageUrl: null,
      });
    }

    if (Number.isNaN(expiresAtMs) || expiresAtMs <= now) {
      return jsonSuccess<SharedRecipeResponse>({
        status: "expired",
        recipe: null,
        expiresAt: row.expires_at,
        imageUrl: null,
      });
    }

    const imageUrl = row.image_path
      ? await createSignedImageUrl(supabase, row.image_path)
      : extractImageUrlFromPayload(row.recipe_payload);

    // Fire and forget metric update. The client response should not depend on this write.
    void supabase.rpc("increment_shared_recipe_link_views", {
      p_share_id: row.id,
    }).then(({ error: rpcError }) => {
      if (rpcError) {
        console.error(
          "[GET SHARED RECIPE] Failed to increment view count:",
          rpcError,
        );
      }
    });

    const recipe = {
      ...row.recipe_payload,
      imageUrl,
    };

    return jsonSuccess<SharedRecipeResponse>({
      status: "active",
      recipe,
      expiresAt: row.expires_at,
      imageUrl,
    });
  } catch (error) {
    console.error("[GET SHARED RECIPE] Error:", error);
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonError(message, 400, "INVALID_REQUEST");
  }
});

function createSupabaseAdminClient(): SupabaseClient {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !supabaseServiceKey) {
    throw new Error("Missing Supabase environment variables");
  }

  return createClient(supabaseUrl, supabaseServiceKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

function getTokenFromRequest(req: Request): string {
  const url = new URL(req.url);
  const queryToken = url.searchParams.get("token")?.trim();
  if (queryToken) {
    return queryToken;
  }

  const pathSegments = url.pathname.split("/").filter(Boolean);
  return pathSegments[pathSegments.length - 1] ?? "";
}

async function createSignedImageUrl(
  supabase: SupabaseClient,
  imagePath: string,
): Promise<string | null> {
  const { data, error } = await supabase.storage
    .from(SHARED_IMAGE_BUCKET)
    .createSignedUrl(imagePath, SIGNED_IMAGE_URL_TTL_SECONDS);

  if (error) {
    console.error("[GET SHARED RECIPE] Failed to sign image URL:", error);
    return null;
  }

  return data?.signedUrl ?? null;
}

function extractImageUrlFromPayload(
  payload: Record<string, unknown>,
): string | null {
  const imageUrl = payload.imageUrl;
  return typeof imageUrl === "string" && imageUrl.trim().length > 0
    ? imageUrl.trim()
    : null;
}

function corsHeaders(): HeadersInit {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
  };
}

function jsonSuccess<T>(data: T, status = 200): Response {
  const body: RestResponse<T> = {
    success: true,
    error: null,
    error_code: null,
    data,
  };

  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(),
      "Content-Type": "application/json",
    },
  });
}

function jsonError(
  message: string,
  status = 500,
  error_code: string | null = null,
): Response {
  const body: RestResponse<null> = {
    success: false,
    error: message,
    error_code,
    data: null,
  };

  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(),
      "Content-Type": "application/json",
    },
  });
}
