set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.increment_ai_imports_used(user_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
$function$
;


