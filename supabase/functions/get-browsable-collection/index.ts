import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { RestResponse } from "../dto/controller-response.ts";

const MAX_PREVIEW_RECIPES = 8;

interface BrowsableCollectionResponse {
  status: "active" | "not_found";
  canonicalSlug: string | null;
  collection: BrowsableCollectionPayload | null;
  recipes: BrowsableCollectionPreviewRecipe[];
  totalVisibleRecipeCount: number;
}

interface BrowsableCollectionPayload {
  title: string | null;
  description: string | null;
  coverImageUrl: string | null;
}

interface BrowsableCollectionPreviewRecipe {
  title: string;
  imageUrl: string | null;
}

interface CollectionRow {
  id: string;
  name: string;
  description: string | null;
  cover_image_url: string | null;
  slug: string | null;
}

interface CollectionRecipeRow {
  recipe_id: string;
  sort_order: number;
}

interface BrowsableRecipeSummaryRow {
  id: string;
  meal_name: string;
  image_url: string | null;
  imported_content_id: string;
}

interface ImportedContentRow {
  id: string;
  content: Record<string, unknown> | null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders() });
  }

  if (req.method !== "GET") {
    return jsonError("Method not allowed", 405, "METHOD_NOT_ALLOWED");
  }

  try {
    const lookup = getCollectionLookupFromRequest(req);
    if (!lookup.slug && !lookup.id) {
      return jsonError(
        "slug or id is required",
        400,
        "MISSING_COLLECTION_IDENTIFIER",
      );
    }

    if (!lookup.slug && lookup.id && !isUuid(lookup.id)) {
      return jsonError("id must be a valid UUID", 400, "INVALID_COLLECTION_ID");
    }

    const supabase = createSupabaseAdminClient();
    const collection = await fetchCollection(supabase, lookup);

    if (!collection) {
      return jsonSuccess<BrowsableCollectionResponse>({
        status: "not_found",
        canonicalSlug: null,
        collection: null,
        recipes: [],
        totalVisibleRecipeCount: 0,
      });
    }

    const orderedCollectionRecipes = await fetchCollectionRecipeOrder(
      supabase,
      collection.id,
    );

    const visibleRecipeSummaries = orderedCollectionRecipes.length > 0
      ? await fetchVisibleRecipeSummaries(
        supabase,
        orderedCollectionRecipes.map((row) => row.recipe_id),
      )
      : [];

    const visibleRecipesById = new Map(
      visibleRecipeSummaries.map((row) => [row.id, row] as const),
    );

    const orderedVisibleRecipes = orderedCollectionRecipes
      .map((row) => visibleRecipesById.get(row.recipe_id))
      .filter(Boolean) as BrowsableRecipeSummaryRow[];

    const previewRows = orderedVisibleRecipes.slice(0, MAX_PREVIEW_RECIPES);
    const previewRecipes = await buildPreviewRecipes(supabase, previewRows);

    void supabase.rpc("increment_collection_views", {
      p_collection_id: collection.id,
    }).then(({ error }) => {
      if (error) {
        console.error(
          "[GET BROWSABLE COLLECTION] Failed to increment view count:",
          error,
        );
      }
    });

    return jsonSuccess<BrowsableCollectionResponse>({
      status: "active",
      canonicalSlug: asNullableTrimmedString(collection.slug),
      collection: {
        title: asNullableTrimmedString(collection.name),
        description: asNullableTrimmedString(collection.description),
        coverImageUrl: asNullableTrimmedString(collection.cover_image_url),
      },
      recipes: previewRecipes,
      totalVisibleRecipeCount: orderedVisibleRecipes.length,
    });
  } catch (error) {
    console.error("[GET BROWSABLE COLLECTION] Error:", error);
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

function getCollectionLookupFromRequest(req: Request): {
  slug: string | null;
  id: string | null;
} {
  const url = new URL(req.url);
  const slug = asNullableTrimmedString(url.searchParams.get("slug"));
  const id = asNullableTrimmedString(url.searchParams.get("id"));

  return { slug, id };
}

async function fetchCollection(
  supabase: SupabaseClient,
  lookup: { slug: string | null; id: string | null },
): Promise<CollectionRow | null> {
  let query = supabase
    .from("collections")
    .select("id, name, description, cover_image_url, slug")
    .eq("visibility", "public");

  if (lookup.slug) {
    query = query.eq("slug", lookup.slug);
  } else if (lookup.id) {
    query = query.eq("id", lookup.id);
  }

  const { data, error } = await query.maybeSingle();

  if (error) {
    console.error(
      "[GET BROWSABLE COLLECTION] Failed to fetch collection:",
      error,
    );
    throw new Error("Failed to fetch collection");
  }

  return data as CollectionRow | null;
}

async function fetchCollectionRecipeOrder(
  supabase: SupabaseClient,
  collectionId: string,
): Promise<CollectionRecipeRow[]> {
  const { data, error } = await supabase
    .from("collection_recipes")
    .select("recipe_id, sort_order")
    .eq("collection_id", collectionId)
    .order("sort_order", { ascending: true });

  if (error) {
    console.error(
      "[GET BROWSABLE COLLECTION] Failed to fetch collection recipe order:",
      error,
    );
    throw new Error("Failed to fetch collection recipes");
  }

  return (data ?? []) as CollectionRecipeRow[];
}

async function fetchVisibleRecipeSummaries(
  supabase: SupabaseClient,
  recipeIds: string[],
): Promise<BrowsableRecipeSummaryRow[]> {
  const { data, error } = await supabase
    .from("browsable_recipes")
    .select("id, meal_name, image_url, imported_content_id")
    .in("id", recipeIds)
    .eq("visibility_status", "published");

  if (error) {
    console.error(
      "[GET BROWSABLE COLLECTION] Failed to fetch visible recipe summaries:",
      error,
    );
    throw new Error("Failed to fetch collection recipes");
  }

  return (data ?? []) as BrowsableRecipeSummaryRow[];
}

async function buildPreviewRecipes(
  supabase: SupabaseClient,
  rows: BrowsableRecipeSummaryRow[],
): Promise<BrowsableCollectionPreviewRecipe[]> {
  const importedContentById = await fetchImportedContentForImageFallback(
    supabase,
    rows,
  );

  return rows.map((row) => {
    const fallbackContent =
      importedContentById.get(row.imported_content_id)?.content ?? {};
    const imageUrl = asNullableTrimmedString(row.image_url) ??
      extractImageUrlFromPayload(fallbackContent);

    return {
      title: asNullableTrimmedString(row.meal_name) ?? "",
      imageUrl,
    };
  });
}

async function fetchImportedContentForImageFallback(
  supabase: SupabaseClient,
  rows: BrowsableRecipeSummaryRow[],
): Promise<Map<string, ImportedContentRow>> {
  const importedContentIds = rows
    .filter((row) => !asNullableTrimmedString(row.image_url))
    .map((row) => row.imported_content_id);

  if (importedContentIds.length === 0) {
    return new Map();
  }

  const { data, error } = await supabase
    .from("imported_content")
    .select("id, content")
    .in("id", importedContentIds);

  if (error) {
    console.error(
      "[GET BROWSABLE COLLECTION] Failed to fetch imported content for previews:",
      error,
    );
    return new Map();
  }

  const rowsById = new Map<string, ImportedContentRow>();
  for (const row of (data ?? []) as ImportedContentRow[]) {
    rowsById.set(row.id, {
      id: row.id,
      content: isPlainObject(row.content) ? row.content : null,
    });
  }

  return rowsById;
}

function extractImageUrlFromPayload(
  payload: Record<string, unknown>,
): string | null {
  const imageUrl = payload.imageUrl ?? payload.image_url;
  return asNullableTrimmedString(imageUrl);
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asNullableTrimmedString(value: unknown): string | null {
  const trimmed = asTrimmedString(value);
  return trimmed.length > 0 ? trimmed : null;
}

function isPlainObject(value: unknown): boolean {
  return typeof value === "object" && value !== null && !Array.isArray(value);
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
