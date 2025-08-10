export const authenticateUser = async (
    supabase: any,
    req: Request,
) => {
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

    // const { data: { session } } = await supabase.auth.signInWithPassword({
    //   email: "user1@test.com",
    //   password: "323211",
    // });

    // const accessToken = session?.access_token;
    // console.log("accessToken", accessToken);

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

    return user;
};
