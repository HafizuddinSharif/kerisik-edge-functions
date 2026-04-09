import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { getAuthenticatedUserOrThrow } from "../utils/auth.ts";
import type { RestResponse } from "../dto/controller-response.ts";

const SHARE_TTL_MS = 3 * 24 * 60 * 60 * 1000;
const SHARED_IMAGE_BUCKET = "shared-recipe-images";
const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const DEFAULT_SHARE_BASE_URL = "https://kerisik.app/shared/recipe";

type Json = Record<string, unknown>;

interface SharedRecipeIngredient {
  name: string;
  quantity?: string | number | null;
  unit?: string | null;
  note?: string | null;
  sortOrder?: number | null;
}

interface SharedRecipeStep {
  text: string;
  sortOrder?: number | null;
}

interface SharedRecipePayload {
  title: string;
  description?: string | null;
  imageUrl?: string | null;
  cookingTime?: number | null;
  servingSuggestions?: number | null;
  ingredients: SharedRecipeIngredient[];
  steps: SharedRecipeStep[];
  attribution?: Json | null;
}

interface ImageUploadInput {
  base64Data: string;
  contentType?: string | null;
  fileName?: string | null;
}

interface CreateRecipeShareRequest {
  recipe: SharedRecipePayload;
  imageUpload?: ImageUploadInput | null;
}

interface CreateRecipeShareResponse {
  shareUrl: string;
  token: string;
  expiresAt: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders() });
  }

  if (req.method !== "POST") {
    return jsonError("Method not allowed", 405, "METHOD_NOT_ALLOWED");
  }

  try {
    const supabase = createSupabaseAdminClient();
    const authUser = await getAuthenticatedUserOrThrow(supabase, req);
    const userProfileId = await getUserProfileIdOrThrow(supabase, authUser.id);

    const body = await req.json() as CreateRecipeShareRequest;
    const recipe = normalizeRecipePayload(body?.recipe);
    const expiresAt = new Date(Date.now() + SHARE_TTL_MS).toISOString();
    const token = generateShareToken();

    let imagePath: string | null = null;
    let imageUrl = recipe.imageUrl ?? null;

    if (body?.imageUpload) {
      try {
        const uploaded = await uploadSharedImage(
          supabase,
          authUser.id,
          token,
          body.imageUpload,
        );
        imagePath = uploaded.path;
        imageUrl = null;
      } catch (uploadError) {
        console.warn(
          "[CREATE RECIPE SHARE] Continuing without uploaded image:",
          uploadError,
        );
      }
    }

    const recipePayloadForStorage: SharedRecipePayload = {
      ...recipe,
      imageUrl,
      attribution: {
        ...(recipe.attribution ?? {}),
        sharedAt: new Date().toISOString(),
      },
    };

    const { error: insertError } = await supabase
      .from("shared_recipe_links")
      .insert({
        token,
        owner_user_profile_id: userProfileId,
        recipe_payload: recipePayloadForStorage,
        image_path: imagePath,
        expires_at: expiresAt,
      });

    if (insertError) {
      if (imagePath) {
        await supabase.storage.from(SHARED_IMAGE_BUCKET).remove([imagePath]);
      }
      console.error("[CREATE RECIPE SHARE] Insert failed:", insertError);
      return jsonError(
        "Failed to create recipe share",
        500,
        "CREATE_SHARE_FAILED",
      );
    }

    const response: CreateRecipeShareResponse = {
      shareUrl: buildShareUrl(token),
      token,
      expiresAt,
    };

    return jsonSuccess(response, 201);
  } catch (error) {
    console.error("[CREATE RECIPE SHARE] Error:", error);
    const message = error instanceof Error ? error.message : "Unknown error";
    const status = isUnauthorizedError(message)
      ? 401
      : isClientError(message)
      ? 400
      : 500;
    const errorCode = isUnauthorizedError(message)
      ? "UNAUTHORIZED"
      : isClientError(message)
      ? "INVALID_REQUEST"
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

async function getUserProfileIdOrThrow(
  supabase: SupabaseClient,
  authUserId: string,
): Promise<string> {
  const { data, error } = await supabase
    .from("user_profile")
    .select("id")
    .eq("auth_id", authUserId)
    .single();

  if (error || !data?.id) {
    throw new Error("User profile not found");
  }

  return data.id as string;
}

function normalizeRecipePayload(input: unknown): SharedRecipePayload {
  if (!input || typeof input !== "object") {
    throw new Error("recipe is required");
  }

  const recipe = input as Record<string, unknown>;
  const title = asTrimmedString(recipe.title);
  if (!title) {
    throw new Error("recipe.title is required");
  }

  const ingredients = Array.isArray(recipe.ingredients)
    ? recipe.ingredients.map(normalizeIngredient).filter(
      Boolean,
    ) as SharedRecipeIngredient[]
    : [];
  const steps = Array.isArray(recipe.steps)
    ? recipe.steps.map(normalizeStep).filter(Boolean) as SharedRecipeStep[]
    : [];

  if (ingredients.length === 0) {
    throw new Error("recipe.ingredients must contain at least one item");
  }

  if (steps.length === 0) {
    throw new Error("recipe.steps must contain at least one item");
  }

  return {
    title,
    description: asNullableTrimmedString(recipe.description),
    imageUrl: asNullableTrimmedString(recipe.imageUrl),
    cookingTime: asNullableNumber(recipe.cookingTime),
    servingSuggestions: asNullableNumber(recipe.servingSuggestions),
    ingredients,
    steps,
    attribution: isPlainObject(recipe.attribution)
      ? recipe.attribution as Json
      : null,
  };
}

function normalizeIngredient(input: unknown): SharedRecipeIngredient | null {
  if (!input || typeof input !== "object") {
    return null;
  }

  const ingredient = input as Record<string, unknown>;
  const name = asTrimmedString(ingredient.name);
  if (!name) {
    return null;
  }

  return {
    name,
    quantity: asNullableStringOrNumber(ingredient.quantity),
    unit: asNullableTrimmedString(ingredient.unit),
    note: asNullableTrimmedString(ingredient.note),
    sortOrder: asNullableNumber(ingredient.sortOrder),
  };
}

function normalizeStep(input: unknown): SharedRecipeStep | null {
  if (!input || typeof input !== "object") {
    return null;
  }

  const step = input as Record<string, unknown>;
  const text = asTrimmedString(step.text);
  if (!text) {
    return null;
  }

  return {
    text,
    sortOrder: asNullableNumber(step.sortOrder),
  };
}

async function uploadSharedImage(
  supabase: SupabaseClient,
  authUserId: string,
  token: string,
  imageUpload: ImageUploadInput,
): Promise<{ path: string }> {
  const contentType = normalizeContentType(imageUpload.contentType);
  const extension = extensionFromContentType(contentType);
  const bytes = decodeBase64Image(imageUpload.base64Data);

  if (bytes.byteLength > MAX_IMAGE_BYTES) {
    throw new Error("imageUpload exceeds 10MB limit");
  }

  const safeFileName = sanitizeFileName(imageUpload.fileName) ??
    `shared-image.${extension}`;
  const path = `shares/${authUserId}/${token}/${safeFileName}`;

  const { error } = await supabase.storage
    .from(SHARED_IMAGE_BUCKET)
    .upload(path, bytes, {
      contentType,
      upsert: false,
    });

  if (error) {
    console.error("[CREATE RECIPE SHARE] Image upload failed:", error);
    throw new Error("Failed to upload shared image");
  }

  return { path };
}

function decodeBase64Image(value: string): Uint8Array {
  const cleaned = value.includes(",") ? value.split(",").pop() ?? "" : value;
  const normalized = cleaned.replace(/\s/g, "");

  if (!normalized) {
    throw new Error("imageUpload.base64Data is required");
  }

  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function normalizeContentType(value: string | null | undefined): string {
  const normalized = (value ?? "").toLowerCase();
  if (normalized === "image/png" || normalized === "image/webp") {
    return normalized;
  }
  return "image/jpeg";
}

function extensionFromContentType(contentType: string): string {
  switch (contentType) {
    case "image/png":
      return "png";
    case "image/webp":
      return "webp";
    default:
      return "jpg";
  }
}

function sanitizeFileName(value: string | null | undefined): string | null {
  const trimmed = asNullableTrimmedString(value);
  if (!trimmed) {
    return null;
  }

  return trimmed.replace(/[^a-zA-Z0-9._-]/g, "-");
}

function generateShareToken(): string {
  return crypto.randomUUID().replace(/-/g, "");
}

function buildShareUrl(token: string): string {
  const baseUrl =
    (Deno.env.get("RECIPE_SHARE_BASE_URL") ?? DEFAULT_SHARE_BASE_URL).replace(
      /\/+$/,
      "",
    );
  return `${baseUrl}/${token}`;
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

function isUnauthorizedError(message: string): boolean {
  return message.includes("Authorization") || message.includes("Invalid token");
}

function isClientError(message: string): boolean {
  return message.includes("recipe") ||
    message.includes("imageUpload") ||
    message.includes("User profile not found");
}

function corsHeaders(): HeadersInit {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
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
