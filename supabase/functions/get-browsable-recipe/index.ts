import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { RestResponse } from "../dto/controller-response.ts";

interface BrowsableRecipeResponse {
  status: "active" | "not_found";
  recipe: Record<string, unknown> | null;
  imageUrl: string | null;
}

interface BrowsableRecipeRow {
  id: string;
  imported_content_id: string;
  meal_name: string;
  meal_description: string | null;
  image_url: string | null;
  cooking_time: number | null;
  serving_suggestions: number | null;
  platform: string;
  original_post_url: string;
  posted_date: string | null;
  author_id: string | null;
}

interface ImportedContentRow {
  content: Record<string, unknown> | null;
}

interface AuthorRow {
  id: string;
  name: string | null;
  handle: string | null;
  profile_url: string | null;
  profile_pic_url: string | null;
  platform: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders() });
  }

  if (req.method !== "GET") {
    return jsonError("Method not allowed", 405, "METHOD_NOT_ALLOWED");
  }

  try {
    const recipeId = getRecipeIdFromRequest(req);
    if (!recipeId) {
      return jsonError("recipeId is required", 400, "MISSING_RECIPE_ID");
    }

    if (!isUuid(recipeId)) {
      return jsonError("recipeId must be a valid UUID", 400, "INVALID_RECIPE_ID");
    }

    const supabase = createSupabaseAdminClient();
    const { data, error } = await supabase
      .from("browsable_recipes")
      .select([
        "id",
        "imported_content_id",
        "meal_name",
        "meal_description",
        "image_url",
        "cooking_time",
        "serving_suggestions",
        "platform",
        "original_post_url",
        "posted_date",
        "author_id",
      ].join(", "))
      .eq("id", recipeId)
      .eq("visibility_status", "published")
      .maybeSingle();

    if (error) {
      console.error("[GET BROWSABLE RECIPE] Query failed:", error);
      return jsonError(
        "Failed to fetch browsable recipe",
        500,
        "FETCH_BROWSABLE_RECIPE_FAILED",
      );
    }

    if (!data) {
      return jsonSuccess<BrowsableRecipeResponse>({
        status: "not_found",
        recipe: null,
        imageUrl: null,
      });
    }

    const row = data as unknown as BrowsableRecipeRow;
    const [importedContent, author] = await Promise.all([
      fetchImportedContent(supabase, row.imported_content_id),
      fetchAuthor(supabase, row.author_id),
    ]);

    const content = importedContent?.content ?? {};
    const imageUrl = asNullableTrimmedString(row.image_url) ??
      extractImageUrlFromPayload(content);

    void supabase.rpc("increment_recipe_views", {
      p_recipe_id: row.id,
    }).then(({ error: rpcError }) => {
      if (rpcError) {
        console.error(
          "[GET BROWSABLE RECIPE] Failed to increment view count:",
          rpcError,
        );
      }
    });

    return jsonSuccess<BrowsableRecipeResponse>({
      status: "active",
      recipe: normalizeBrowsableRecipePayload(row, content, author, imageUrl),
      imageUrl,
    });
  } catch (error) {
    console.error("[GET BROWSABLE RECIPE] Error:", error);
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

function getRecipeIdFromRequest(req: Request): string {
  const url = new URL(req.url);
  const queryRecipeId = url.searchParams.get("recipeId")?.trim();
  if (queryRecipeId) {
    return queryRecipeId;
  }

  const pathSegments = url.pathname.split("/").filter(Boolean);
  return pathSegments[pathSegments.length - 1] ?? "";
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

async function fetchImportedContent(
  supabase: SupabaseClient,
  importedContentId: string,
): Promise<ImportedContentRow | null> {
  const { data, error } = await supabase
    .from("imported_content")
    .select("content")
    .eq("id", importedContentId)
    .maybeSingle();

  if (error) {
    console.error(
      "[GET BROWSABLE RECIPE] Failed to fetch imported content:",
      error,
    );
    return null;
  }

  if (!data || !isPlainObject(data.content)) {
    return null;
  }

  return { content: data.content as Record<string, unknown> };
}

async function fetchAuthor(
  supabase: SupabaseClient,
  authorId: string | null,
): Promise<AuthorRow | null> {
  if (!authorId) {
    return null;
  }

  const { data, error } = await supabase
    .from("authors")
    .select("id, name, handle, profile_url, profile_pic_url, platform")
    .eq("id", authorId)
    .maybeSingle();

  if (error) {
    console.error("[GET BROWSABLE RECIPE] Failed to fetch author:", error);
    return null;
  }

  return data as unknown as AuthorRow | null;
}

function normalizeBrowsableRecipePayload(
  row: BrowsableRecipeRow,
  content: Record<string, unknown>,
  author: AuthorRow | null,
  imageUrl: string | null,
): Record<string, unknown> {
  return {
    title: asNullableTrimmedString(row.meal_name) ??
      asNullableTrimmedString(content.meal_name) ??
      "",
    description: asNullableTrimmedString(row.meal_description) ??
      asNullableTrimmedString(content.meal_description),
    imageUrl,
    cookingTime: row.cooking_time ?? asNullableNumber(content.cooking_time),
    servingSuggestions: row.serving_suggestions ??
      asNullableNumber(content.serving_suggestions) ??
      asNullableNumber(content.serving_suggestion),
    ingredients: normalizeIngredientGroups(content.ingredients),
    steps: normalizeStepGroups(content.steps),
    attribution: buildAttribution(content.attribution, row, author),
  };
}

function buildAttribution(
  input: unknown,
  row: BrowsableRecipeRow,
  author: AuthorRow | null,
): Record<string, unknown> {
  const base = isPlainObject(input) ? { ...input as Record<string, unknown> } : {};

  return {
    ...base,
    source: "browsable_recipe",
    recipeId: row.id,
    platform: row.platform,
    originalPostUrl: row.original_post_url,
    postedDate: row.posted_date,
    author: author
      ? {
        id: author.id,
        name: author.name,
        handle: author.handle,
        profileUrl: author.profile_url,
        profilePicUrl: author.profile_pic_url,
        platform: author.platform,
      }
      : null,
  };
}

function extractImageUrlFromPayload(
  payload: Record<string, unknown>,
): string | null {
  const imageUrl = payload.imageUrl ?? payload.image_url;
  return asNullableTrimmedString(imageUrl);
}

interface SharedRecipeIngredient {
  name: string;
  quantity?: string | number | null;
  unit?: string | null;
  note?: string | null;
  sortOrder?: number | null;
}

interface SharedRecipeIngredientGroup {
  name: string;
  sub_ingredients: SharedRecipeIngredient[];
  sortOrder?: number | null;
}

interface SharedRecipeStepGroup {
  name: string;
  sub_steps: string[];
}

function normalizeIngredient(input: unknown): SharedRecipeIngredient | null {
  if (!input || typeof input !== "object") {
    return null;
  }

  const ingredient = input as Record<string, unknown>;
  const name = asNullableTrimmedString(ingredient.name);
  if (!name) {
    return null;
  }

  return {
    name,
    quantity: asNullableStringOrNumber(ingredient.quantity),
    unit: asNullableTrimmedString(ingredient.unit),
    note: asNullableTrimmedString(ingredient.note),
    sortOrder: asNullableNumber(ingredient.sortOrder ?? ingredient.sort_order),
  };
}

function normalizeIngredientGroups(
  input: unknown,
): SharedRecipeIngredientGroup[] {
  if (!Array.isArray(input)) {
    return [];
  }

  const looksGrouped = input.some((item) =>
    isPlainObject(item) && Array.isArray(item.sub_ingredients)
  );

  if (!looksGrouped) {
    const legacyItems = input.map(normalizeIngredient).filter(Boolean) as
      SharedRecipeIngredient[];
    return legacyItems.length > 0
      ? [{ name: "Ingredients", sub_ingredients: legacyItems, sortOrder: 1 }]
      : [];
  }

  return input.map(normalizeIngredientGroup).filter(Boolean) as
    SharedRecipeIngredientGroup[];
}

function normalizeIngredientGroup(
  input: unknown,
): SharedRecipeIngredientGroup | null {
  if (!input || typeof input !== "object") {
    return null;
  }

  const group = input as Record<string, unknown>;
  const name = asNullableTrimmedString(group.name);
  const subIngredients = Array.isArray(group.sub_ingredients)
    ? group.sub_ingredients.map(normalizeIngredient).filter(Boolean) as
      SharedRecipeIngredient[]
    : [];

  if (!name || subIngredients.length === 0) {
    return null;
  }

  return {
    name,
    sub_ingredients: subIngredients,
    sortOrder: asNullableNumber(group.sortOrder ?? group.sort_order),
  };
}

function normalizeStep(input: unknown): string | null {
  if (typeof input === "string") {
    return asNullableTrimmedString(input);
  }

  if (!input || typeof input !== "object") {
    return null;
  }

  const step = input as Record<string, unknown>;
  return asNullableTrimmedString(step.text);
}

function normalizeStepGroups(input: unknown): SharedRecipeStepGroup[] {
  if (!Array.isArray(input)) {
    return [];
  }

  const looksGrouped = input.some((item) =>
    isPlainObject(item) && Array.isArray(item.sub_steps)
  );

  if (!looksGrouped) {
    const legacyItems = input.map(normalizeStep).filter(Boolean) as string[];
    return legacyItems.length > 0
      ? [{ name: "Steps", sub_steps: legacyItems }]
      : [];
  }

  return input.map(normalizeStepGroup).filter(Boolean) as SharedRecipeStepGroup[];
}

function normalizeStepGroup(input: unknown): SharedRecipeStepGroup | null {
  if (!input || typeof input !== "object") {
    return null;
  }

  const group = input as Record<string, unknown>;
  const name = asNullableTrimmedString(group.name);
  const subSteps = Array.isArray(group.sub_steps)
    ? group.sub_steps.map(normalizeSubStep).filter(Boolean) as string[]
    : [];

  if (!name || subSteps.length === 0) {
    return null;
  }

  return {
    name,
    sub_steps: subSteps,
  };
}

function normalizeSubStep(input: unknown): string | null {
  return normalizeStep(input);
}

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asNullableTrimmedString(value: unknown): string | null {
  const trimmed = asTrimmedString(value);
  return trimmed.length > 0 ? trimmed : null;
}

function asNullableNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  return null;
}

function asNullableStringOrNumber(value: unknown): string | number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  const stringValue = asNullableTrimmedString(value);
  return stringValue ?? null;
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
