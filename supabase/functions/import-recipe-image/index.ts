import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import { getAuthenticatedUserOrThrow } from "../utils/auth.ts";

const prefix = "supabase://scan-uploads/";
Deno.serve(async (req) => {
  try {
    const { image_pointers, email, caption } = await req.json();
    if (!Array.isArray(image_pointers) || image_pointers.length < 1 || image_pointers.length > 5) return Response.json({ success: false, error: "Provide 1–5 images or one PDF" }, { status: 422 });
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const user = await getAuthenticatedUserOrThrow(supabase, req);
    for (const pointer of image_pointers) {
      const path = typeof pointer === "string" && pointer.startsWith(prefix) ? pointer.slice(prefix.length) : "";
      if (path.split("/")[0] !== user.id) return Response.json({ success: false, error: "Scan upload does not belong to this user" }, { status: 403 });
    }
    const response = await fetch(`${Deno.env.get("MS_LLM_BASE_URL") ?? "http://host.docker.internal:8000"}/api/v2/import-from-image`, {
      method: "POST", headers: { "Content-Type": "application/json", ...(Deno.env.get("MS_LLM_API_KEY") ? { "x-api-key": Deno.env.get("MS_LLM_API_KEY")! } : {}) },
      body: JSON.stringify({ image_pointers, email, caption }),
    });
    return new Response(await response.text(), { status: response.status, headers: { "Content-Type": "application/json" } });
  } catch (error) {
    return Response.json({ success: false, error: error instanceof Error ? error.message : "Unauthorized" }, { status: 401 });
  }
});
