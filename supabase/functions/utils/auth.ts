import type { SupabaseClient, User } from "jsr:@supabase/supabase-js@2";

export const authenticateUser = async (
    supabase: SupabaseClient,
    req: Request,
): Promise<User | Response> => {
    // Get the authorization header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
        console.log("No authorization header found");
        return new Response(
            JSON.stringify({ error: "Authorization header required" }),
            {
                status: 401,
                headers: { "Content-Type": "application/json" },
            },
        );
    }

    // // Extract the JWT token
    const token = authHeader.replace("Bearer ", "");

    // Verify the JWT token and get user info
    const { data: { user }, error: userError } = await supabase.auth.getUser(
        token,
    );
    if (userError || !user) {
        return new Response(
            JSON.stringify({ error: "Invalid token" }),
            {
                status: 401,
                headers: { "Content-Type": "application/json" },
            },
        );
    }

    return user as unknown as User;
};

export const getAuthenticatedUserOrThrow = async (
    supabase: SupabaseClient,
    req: Request,
): Promise<User> => {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
        throw new Error("Authorization header required");
    }

    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: userError } = await supabase.auth.getUser(
        token,
    );

    if (userError || !user) {
        throw new Error("Invalid token");
    }

    return user as unknown as User;
};
