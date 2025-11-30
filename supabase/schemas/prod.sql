

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "pgsodium";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."create_user_on_signup"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO public.user_profile (id, auth_id, email, is_pro, ai_imports_used)
  VALUES (gen_random_uuid(), new.id, new.email, FALSE, 0);
  RETURN new;
END;
$$;


ALTER FUNCTION "public"."create_user_on_signup"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."increment_ai_imports_used"("user_id" "uuid") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    new_count integer;
BEGIN
    UPDATE public.user_profile 
    SET ai_imports_used = ai_imports_used + 1,
        modified_at = now()
    WHERE id = user_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User profile not found for user_id: %', user_id;
    END IF;
    
    SELECT ai_imports_used INTO new_count 
    FROM public.user_profile 
    WHERE id = user_id;
    
    RETURN new_count;
END;
$$;

ALTER FUNCTION "public"."increment_ai_imports_used"("uuid") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."user_profile" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "auth_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "modified_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    "is_pro" boolean DEFAULT false NOT NULL,
    "ai_imports_used" integer DEFAULT 0 NOT NULL,
    "email" "text"
);


ALTER TABLE "public"."user_profile" OWNER TO "postgres";


ALTER TABLE ONLY "public"."user_profile"
    ADD CONSTRAINT "user_profile_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."user_profile"
    ADD CONSTRAINT "user_profile_auth_id_key" UNIQUE ("auth_id");


ALTER TABLE ONLY "public"."user_profile"
    ADD CONSTRAINT "user_profile_auth_id_fkey" FOREIGN KEY ("auth_id") REFERENCES "auth"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



CREATE POLICY "Enable users to view their own data only" ON "public"."user_profile" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "auth_id"));



ALTER TABLE "public"."user_profile" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";




















































































































































































GRANT ALL ON FUNCTION "public"."create_user_on_signup"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_user_on_signup"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_user_on_signup"() TO "service_role";

GRANT ALL ON FUNCTION "public"."increment_ai_imports_used"("uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."increment_ai_imports_used"("uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_ai_imports_used"("uuid") TO "service_role";



























GRANT ALL ON TABLE "public"."user_profile" TO "anon";
GRANT ALL ON TABLE "public"."user_profile" TO "authenticated";
GRANT ALL ON TABLE "public"."user_profile" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";






























RESET ALL;
