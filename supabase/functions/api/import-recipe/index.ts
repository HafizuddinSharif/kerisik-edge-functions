// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { MSLLMClient } from "../../utils/ms-llm.ts";
import { createClient } from "@supabase/supabase-js";
import { ImportFromUrlResponse } from "../../dto/controller-response.ts";

Deno.serve(async (req) => {
  try {
    const { url } = await req.json();

    // Get the authorization header
    // const authHeader = req.headers.get("Authorization");
    // if (!authHeader) {
    //   return new Response(
    //     JSON.stringify({ error: "Authorization header required" }),
    //     {
    //       status: 401,
    //       headers: { "Content-Type": "application/json" },
    //     },
    //   );
    // }

    // // Extract the JWT token
    // const token = authHeader.replace("Bearer ", "");

    // Create Supabase client
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Verify the JWT token and get user info
    // const { data: { user }, error: userError } = await supabase.auth.getUser(
    //   token,
    // );
    // if (userError || !user) {
    //   return new Response(
    //     JSON.stringify({ error: "Invalid token" }),
    //     {
    //       status: 401,
    //       headers: { "Content-Type": "application/json" },
    //     },
    //   );
    // }

    // Check if the URL is already in the database
    console.log("Checking if URL is already in the database", url);
    const { data: existingContent, error: existingError } = await supabase
      .from("imported_content")
      .select("*")
      .eq("source_url", url)
      .order("created_at", { ascending: false })
      .limit(1)
      .single();

    if (existingContent) {
      const mealContent: ImportFromUrlResponse = existingContent.metadata;
      console.log("Found in DB for:", mealContent.content.meal_name);
      // verify mealContent follows the ImportFromUrlResponse interface
      return new Response(
        JSON.stringify(mealContent),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    // Call the MS LLM API
    const msLLM = new MSLLMClient();
    const response = await msLLM.callAPI("/extract-content", {
      url,
    }, "POST");

    // Store the response in the database
    const { data: importedContent, error: insertError } = await supabase
      .from("imported_content")
      .insert({
        user_id: "12f5bae4-fba3-439f-93d5-d0e5a3bb4978",
        source_url: url,
        content: response.choices?.[0]?.message?.content ||
          JSON.stringify(response),
        metadata: response,
      })
      .select()
      .single();

    if (insertError) {
      console.error("Error inserting content:", insertError);
      const errorResponse: ImportFromUrlResponse = {
        success: false,
        url,
        content: {
          meal_name: "",
          ingredients: [],
          instructions: [],
          meal_description: "",
          able_to_extract: false,
          serving_suggestion: 0,
          cooking_time: 0,
        },
        metadata: {},
        error: "Failed to store content",
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
    // const { error: updateError } = await supabase
    //   .from("user_profile")
    //   .update({
    //     ai_imports_used: supabase.sql`ai_imports_used + 1`,
    //     modified_at: new Date().toISOString(),
    //   })
    //   .eq("id", user.id);

    // if (updateError) {
    //   console.error("Error updating user profile:", updateError);
    //   // Don't fail the request if this fails, just log it
    // }

    // Parse the response to extract meal content
    const responseContent = response.choices?.[0]?.message?.content;
    let mealContent;

    try {
      if (responseContent) {
        mealContent = JSON.parse(responseContent);
      }
    } catch (parseError) {
      console.error("Error parsing response content:", parseError);
    }

    // Create type-safe response
    const successResponse: ImportFromUrlResponse = {
      success: true,
      url,
      content: mealContent || {
        meal_name: "",
        ingredients: [],
        instructions: [],
        meal_description: "",
        able_to_extract: false,
        serving_suggestion: 0,
        cooking_time: 0,
      },
      metadata: {
        model: response.model || "",
        created: response.created?.toString() || "",
        usage: JSON.stringify(response.usage || {}),
        choices_count: response.choices?.length?.toString() || "0",
      },
      error: null,
    };

    return new Response(
      JSON.stringify(successResponse),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error in import-from-url function:", error);
    const errorResponse: ImportFromUrlResponse = {
      success: false,
      url: "",
      content: {
        meal_name: "",
        ingredients: [],
        instructions: [],
        meal_description: "",
        able_to_extract: false,
        serving_suggestion: 0,
        cooking_time: 0,
      },
      metadata: {},
      error: error instanceof Error ? error.message : "Unknown error",
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
