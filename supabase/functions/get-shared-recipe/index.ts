import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { RestResponse } from "../dto/controller-response.ts";

const SHARED_IMAGE_BUCKET = "shared-recipe-images";
const SIGNED_IMAGE_URL_TTL_SECONDS = 60 * 60;
const REQUESTS_PER_MINUTE_LIMIT = 30;
const VIEWER_ID_HEADER = "x-viewer-id";

interface SharedRecipeResponse {
  status: "active" | "expired" | "revoked" | "not_found";
  recipe: Record<string, unknown> | null;
  expiresAt: string | null;
  imageUrl: string | null;
}

interface RateLimitResult {
  allowed: boolean;
  request_count: number;
  remaining: number;
  limit_value: number;
  reset_at: string;
  retry_after_seconds: number;
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
    const clientIp = getClientIpFromRequest(req);
    const clientIpHash = await sha256Hex(clientIp);
    const rateLimitHeaders = await getRateLimitHeaders(
      supabase,
      token,
      clientIpHash,
    );

    if (rateLimitHeaders.blocked) {
      return jsonError(
        "Too many requests",
        429,
        "RATE_LIMITED",
        rateLimitHeaders.headers,
      );
    }

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
        rateLimitHeaders.headers,
      );
    }

    if (!data) {
      return jsonSuccess<SharedRecipeResponse>({
        status: "not_found",
        recipe: null,
        expiresAt: null,
        imageUrl: null,
      }, 200, rateLimitHeaders.headers);
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
      }, 200, rateLimitHeaders.headers);
    }

    if (Number.isNaN(expiresAtMs) || expiresAtMs <= now) {
      return jsonSuccess<SharedRecipeResponse>({
        status: "expired",
        recipe: null,
        expiresAt: row.expires_at,
        imageUrl: null,
      }, 200, rateLimitHeaders.headers);
    }

    const imageUrl = row.image_path
      ? await createSignedImageUrl(supabase, row.image_path)
      : extractImageUrlFromPayload(row.recipe_payload);
    const viewerKey = getViewerKeyFromRequest(req, clientIp);
    const viewerKeyHash = await sha256Hex(viewerKey);

    // Fire and forget metric update. The client response should not depend on this write.
    void supabase.rpc("increment_shared_recipe_link_views", {
      p_share_id: row.id,
      p_viewer_key_hash: viewerKeyHash,
    }).then(({ error: rpcError }) => {
      if (rpcError) {
        console.error(
          "[GET SHARED RECIPE] Failed to increment view count:",
          rpcError,
        );
      }
    });

    const recipe = {
      ...normalizeSharedRecipePayload(row.recipe_payload),
      imageUrl,
    };

    return jsonSuccess<SharedRecipeResponse>({
      status: "active",
      recipe,
      expiresAt: row.expires_at,
      imageUrl,
    }, 200, rateLimitHeaders.headers);
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

function getClientIpFromRequest(req: Request): string {
  const candidates = [
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim(),
    req.headers.get("x-real-ip")?.trim(),
    req.headers.get("cf-connecting-ip")?.trim(),
    req.headers.get("fly-client-ip")?.trim(),
  ];

  for (const candidate of candidates) {
    if (candidate) {
      return candidate;
    }
  }

  return "unknown";
}

function getViewerKeyFromRequest(req: Request, clientIp: string): string {
  const headerValue = req.headers.get(VIEWER_ID_HEADER);
  const trimmed = headerValue?.trim();
  if (trimmed) {
    return trimmed.slice(0, 256);
  }

  return `ip:${clientIp}`;
}

async function sha256Hex(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function getRateLimitHeaders(
  supabase: SupabaseClient,
  token: string,
  clientIpHash: string,
): Promise<{ blocked: boolean; headers: Record<string, string> }> {
  const { data, error } = await supabase.rpc(
    "check_shared_recipe_link_rate_limit",
    {
      p_token: token,
      p_client_ip_hash: clientIpHash,
      p_window_started_at: new Date().toISOString(),
      p_limit: REQUESTS_PER_MINUTE_LIMIT,
    },
  );

  if (error) {
    console.error("[GET SHARED RECIPE] Rate limit check failed:", error);
    return {
      blocked: false,
      headers: {},
    };
  }

  const row = Array.isArray(data) ? (data[0] as RateLimitResult | null) : null;
  if (!row) {
    return {
      blocked: false,
      headers: {},
    };
  }

  const headers: Record<string, string> = {
    "X-RateLimit-Limit": String(row.limit_value),
    "X-RateLimit-Remaining": String(row.remaining),
    "X-RateLimit-Reset": new Date(row.reset_at).toISOString(),
  };

  if (!row.allowed) {
    headers["Retry-After"] = String(row.retry_after_seconds);
  }

  return {
    blocked: !row.allowed,
    headers,
  };
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

function normalizeSharedRecipePayload(
  payload: Record<string, unknown>,
): Record<string, unknown> {
  return {
    ...payload,
    steps: normalizeSharedRecipeSteps(payload.steps),
  };
}

function normalizeSharedRecipeSteps(input: unknown): Array<Record<string, unknown>> {
  if (!Array.isArray(input)) {
    return [];
  }

  return input
    .map((group) => normalizeSharedRecipeStepGroup(group))
    .filter(Boolean) as Array<Record<string, unknown>>;
}

function normalizeSharedRecipeStepGroup(
  input: unknown,
): Record<string, unknown> | null {
  if (!input || typeof input !== "object") {
    return null;
  }

  const group = input as Record<string, unknown>;
  const name = asTrimmedString(group.name);
  const subSteps = normalizeSharedRecipeSubSteps(group.sub_steps);

  if (!name || subSteps.length === 0) {
    return null;
  }

  return {
    name,
    sub_steps: subSteps,
  };
}

function normalizeSharedRecipeSubSteps(input: unknown): string[] {
  if (!Array.isArray(input)) {
    return [];
  }

  return input.map(normalizeSharedRecipeSubStep).filter(Boolean) as string[];
}

function normalizeSharedRecipeSubStep(input: unknown): string | null {
  if (typeof input === "string") {
    return asTrimmedString(input);
  }

  if (!input || typeof input !== "object") {
    return null;
  }

  const step = input as Record<string, unknown>;
  return asTrimmedString(step.text);
}

function asTrimmedString(input: unknown): string | null {
  if (typeof input !== "string") {
    return null;
  }

  const trimmed = input.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function corsHeaders(): HeadersInit {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      `authorization, x-client-info, apikey, content-type, ${VIEWER_ID_HEADER}`,
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Expose-Headers":
      "Retry-After, X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Reset",
  };
}

function jsonSuccess<T>(
  data: T,
  status = 200,
  extraHeaders: HeadersInit = {},
): Response {
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
      ...extraHeaders,
      "Content-Type": "application/json",
    },
  });
}

function jsonError(
  message: string,
  status = 500,
  error_code: string | null = null,
  extraHeaders: HeadersInit = {},
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
      ...extraHeaders,
      "Content-Type": "application/json",
    },
  });
}
