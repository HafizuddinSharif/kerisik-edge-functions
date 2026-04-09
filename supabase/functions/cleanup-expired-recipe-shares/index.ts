import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { RestResponse } from "../dto/controller-response.ts";

const SHARED_IMAGE_BUCKET = "shared-recipe-images";
const DEFAULT_BATCH_SIZE = 100;
const MAX_BATCH_SIZE = 500;

interface CleanupCandidateRow {
  id: string;
  image_path: string | null;
}

interface CleanupExpiredRecipeSharesResponse {
  deletedShareCount: number;
  deletedImageCount: number;
  skippedShareCount: number;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders() });
  }

  if (req.method !== "POST") {
    return jsonError("Method not allowed", 405, "METHOD_NOT_ALLOWED");
  }

  try {
    authorizeCronRequest(req);

    const batchSize = getBatchSizeFromRequest(req);
    const supabase = createSupabaseAdminClient();
    const rows = await getCleanupCandidates(supabase, batchSize);

    if (rows.length === 0) {
      return jsonSuccess<CleanupExpiredRecipeSharesResponse>({
        deletedShareCount: 0,
        deletedImageCount: 0,
        skippedShareCount: 0,
      });
    }

    const imagePaths = Array.from(
      new Set(
        rows
          .map((row) => row.image_path)
          .filter((path): path is string =>
            typeof path === "string" && path.length > 0
          ),
      ),
    );

    const imageDeleteResult = await deleteSharedImages(supabase, imagePaths);
    const shareIdsToDelete = rows
      .filter((row) =>
        !row.image_path || imageDeleteResult.deletedPaths.has(row.image_path)
      )
      .map((row) => row.id);

    if (shareIdsToDelete.length > 0) {
      const { error } = await supabase
        .from("shared_recipe_links")
        .delete()
        .in("id", shareIdsToDelete);

      if (error) {
        console.error(
          "[CLEANUP SHARED RECIPE SHARES] Failed to delete rows:",
          error,
        );
        return jsonError(
          "Failed to delete expired share rows",
          500,
          "DELETE_SHARES_FAILED",
        );
      }
    }

    return jsonSuccess<CleanupExpiredRecipeSharesResponse>({
      deletedShareCount: shareIdsToDelete.length,
      deletedImageCount: imageDeleteResult.deletedPaths.size,
      skippedShareCount: rows.length - shareIdsToDelete.length,
    });
  } catch (error) {
    console.error("[CLEANUP SHARED RECIPE SHARES] Error:", error);
    const message = error instanceof Error ? error.message : "Unknown error";
    const status = message.includes("Unauthorized") ? 401 : 500;
    const errorCode = message.includes("Unauthorized")
      ? "UNAUTHORIZED"
      : "INTERNAL_ERROR";
    return jsonError(message, status, errorCode);
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

function authorizeCronRequest(req: Request): void {
  const expectedSecret = Deno.env.get("RECIPE_SHARE_CLEANUP_CRON_SECRET");
  const providedSecret = req.headers.get("x-cron-secret");

  if (!expectedSecret) {
    throw new Error("Unauthorized: missing RECIPE_SHARE_CLEANUP_CRON_SECRET");
  }

  if (!providedSecret || providedSecret !== expectedSecret) {
    throw new Error("Unauthorized");
  }
}

function getBatchSizeFromRequest(req: Request): number {
  const url = new URL(req.url);
  const raw = Number.parseInt(url.searchParams.get("batchSize") ?? "", 10);

  if (!Number.isFinite(raw) || raw <= 0) {
    return DEFAULT_BATCH_SIZE;
  }

  return Math.min(raw, MAX_BATCH_SIZE);
}

async function getCleanupCandidates(
  supabase: SupabaseClient,
  batchSize: number,
): Promise<CleanupCandidateRow[]> {
  const { data, error } = await supabase.rpc(
    "get_expired_shared_recipe_links_for_cleanup",
    { p_limit: batchSize },
  );

  if (error) {
    console.error(
      "[CLEANUP SHARED RECIPE SHARES] Failed to fetch candidates:",
      error,
    );
    throw new Error("Failed to load cleanup candidates");
  }

  return (data ?? []) as CleanupCandidateRow[];
}

async function deleteSharedImages(
  supabase: SupabaseClient,
  imagePaths: string[],
): Promise<{ deletedPaths: Set<string> }> {
  if (imagePaths.length === 0) {
    return { deletedPaths: new Set<string>() };
  }

  const { data, error } = await supabase.storage
    .from(SHARED_IMAGE_BUCKET)
    .remove(imagePaths);

  if (error) {
    console.error(
      "[CLEANUP SHARED RECIPE SHARES] Failed to delete images:",
      error,
    );
    return { deletedPaths: new Set<string>() };
  }

  const deletedPaths = new Set<string>();
  for (const item of data ?? []) {
    if (item?.name) {
      deletedPaths.add(item.name);
    }
  }

  return { deletedPaths };
}

function corsHeaders(): HeadersInit {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-cron-secret",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
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
