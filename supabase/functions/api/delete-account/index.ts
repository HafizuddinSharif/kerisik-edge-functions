// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { getAuthenticatedUserOrThrow } from "../../utils/auth.ts";
import type { RestResponse } from "../../dto/controller-response.ts";

/**
 * Delete account edge function:
 * - Anonymizes imported_content rows by setting user_id = NULL
 * - Deletes the user_profile row
 * - Deletes the auth.users record via Admin API
 */
Deno.serve(async (req) => {
  try {
    console.log("[DELETE ACCOUNT] ===== START: Deleting user account =====");

    // Only allow POST requests
    if (req.method !== "POST") {
      return jsonError("Method not allowed", 405);
    }

    // Create Supabase service-role client for admin operations
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseServiceKey) {
      console.error("[DELETE ACCOUNT] Missing Supabase environment variables");
      return jsonError("Server configuration error", 500);
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });

    // Authenticate the user
    const authUser = await getAuthenticatedUserOrThrow(supabase, req);
    console.log("[DELETE ACCOUNT] Authenticated user ID:", authUser.id);

    // Lookup user_profile.id via auth_id
    const { data: profile, error: profileError } = await supabase
      .from("user_profile")
      .select("id")
      .eq("auth_id", authUser.id)
      .single();

    if (profileError || !profile) {
      return jsonError("User profile not found", 404);
    }

    const profileId = profile.id;
    console.log("[DELETE ACCOUNT] Found user profile ID:", profileId);

    // Anonymize imported_content by setting user_id = NULL
    const { error: updateError } = await supabase
      .from("imported_content")
      .update({ user_id: null })
      .eq("user_id", profileId);

    if (updateError) {
      return jsonError(
        "Failed to anonymize imported content",
        500,
        "ANONYMIZE_ERROR",
      );
    }

    console.log("[DELETE ACCOUNT] Successfully anonymized imported_content");

    // Delete the user_profile row
    console.log("[DELETE ACCOUNT] Deleting user profile...");
    const { error: deleteProfileError } = await supabase
      .from("user_profile")
      .delete()
      .eq("id", profileId);

    if (deleteProfileError) {
      console.error(
        "[DELETE ACCOUNT] Error deleting user profile:",
        deleteProfileError,
      );
      return jsonError(
        "Failed to delete user profile",
        500,
        "DELETE_PROFILE_ERROR",
      );
    }

    // Delete the auth user via Admin API
    const { error: deleteAuthError } = await supabase.auth.admin.deleteUser(
      authUser.id,
    );

    if (deleteAuthError) {
      console.error(
        "[DELETE ACCOUNT] Error deleting auth user:",
        deleteAuthError,
      );
      return jsonError("Failed to delete auth user", 500, "DELETE_AUTH_ERROR");
    }

    return jsonSuccess({ message: "Account deleted successfully" });
  } catch (error) {
    console.error(
      "[DELETE ACCOUNT] ===== ERROR: Exception caught in main handler =====",
    );
    console.error("[DELETE ACCOUNT] Error type:", error?.constructor?.name);
    console.error(
      "[DELETE ACCOUNT] Error message:",
      error instanceof Error ? error.message : String(error),
    );
    console.error(
      "[DELETE ACCOUNT] Error stack:",
      error instanceof Error ? error.stack : "No stack trace",
    );

    const message = error instanceof Error ? error.message : "Unknown error";
    const status =
      error instanceof Error && error.message.includes("Authorization")
        ? 401
        : 500;
    return jsonError(message, status);
  }
});

// Helper functions
function jsonSuccess<T>(data: T): Response {
  const body: RestResponse<T> = {
    success: true,
    error: null,
    error_code: null,
    data,
  };
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
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
    headers: { "Content-Type": "application/json" },
  });
}
