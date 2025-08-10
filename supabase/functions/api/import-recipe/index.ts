// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { MSLLMClient } from "../../utils/ms-llm.ts";
import { createClient } from "@supabase/supabase-js";
import {
  ImportFromUrlResponse,
  RestResponse,
} from "../../dto/controller-response.ts";
import { authenticateUser } from "../../utils/auth.ts";

Deno.serve(async (req) => {
  try {
    const { url } = await req.json();
    const sanitizedUrl = await sanitizeUrl(url);

    // Create Supabase client
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Authenticate the user
    const user = await authenticateUser(supabase, req);

    const userId = user.id;

    // Check if the URL is already in the database
    const { data: existingContent } = await supabase
      .from("imported_content")
      .select("*")
      .eq("source_url", sanitizedUrl)
      .order("created_at", { ascending: false })
      .limit(1)
      .single();

    if (existingContent) {
      const mealContent: ImportFromUrlResponse = {
        content: existingContent.content,
        metadata: existingContent.metadata,
      };
      // verify mealContent follows the ImportFromUrlResponse interface
      const restResponse: RestResponse<ImportFromUrlResponse> = {
        success: true,
        error: null,
        error_code: null,
        data: mealContent,
      };

      return new Response(
        JSON.stringify(restResponse),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    // Call the MS LLM API
    const msLLM = new MSLLMClient();
    const response = await msLLM.callAPI("/extract-content", {
      url: sanitizedUrl,
    }, "POST");

    if (!response.success) {
      return new Response(
        JSON.stringify(response),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    // Store the response in the database
    const { data: importedContent, error: insertError } = await supabase
      .from("imported_content")
      .insert({
        user_id: userId,
        source_url: sanitizedUrl,
        content: response.data?.content || null,
        metadata: response.data?.metadata || null,
      })
      .select()
      .single();

    if (insertError) {
      console.error("Error inserting content:", insertError);
      const errorResponse: RestResponse<ImportFromUrlResponse> = {
        success: false,
        error: "Failed to store content",
        error_code: null,
        data: null,
      };
      return new Response(
        JSON.stringify(errorResponse),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Update the user's ai_imports_used counter
    console.log("Updating AI import used counter");
    const { data, error } = await supabase
      .rpc("increment_ai_imports_used", {
        user_id: userId,
      });

    if (error) {
      console.error("Error updating user profile:", error);
    }

    // Parse the response to extract meal content
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

    return new Response(
      JSON.stringify(restResponse),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error in import-from-url function:", error);

    const errorObj = error as { error: string; success: boolean };
    console.error("Error details:", errorObj.error);

    const errorResponse: RestResponse<ImportFromUrlResponse> = {
      success: false,
      error: error instanceof Error ? error.message : "Unknown error",
      error_code: null,
      data: null,
    };
    return new Response(
      JSON.stringify(errorResponse),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});

const sanitizeUrl = async (url: string): Promise<string> => {
  // Resolve short links (vt.tiktok.com, vm.tiktok.com, ig.me, etc.)
  const res = await fetch(url, { redirect: "follow" });
  const finalUrl = res.url;

  let platform = null;
  let minimalUrl = null;

  // TikTok → keep only https://www.tiktok.com/video/<video_id>
  if (finalUrl.includes("tiktok.com")) {
    const match = finalUrl.match(/\/video\/(\d+)/);
    if (match) {
      platform = "tiktok";
      minimalUrl = `https://www.tiktok.com/video/${match[1]}`;
    }
  } // Instagram → keep only https://www.instagram.com/reel/<shortcode>/
  else if (finalUrl.includes("instagram.com")) {
    const match = finalUrl.match(/\/reel\/([A-Za-z0-9_-]+)/);
    if (match) {
      platform = "instagram_reel";
      minimalUrl = `https://www.instagram.com/reel/${match[1]}/`;
    }
  }

  if (!minimalUrl) {
    throw new Error("Unsupported URL or ID not found");
  }

  return finalUrl;
};
