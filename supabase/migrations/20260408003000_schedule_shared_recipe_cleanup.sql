-- Migration: 20260408003000_schedule_shared_recipe_cleanup
-- Description: Cleanup expired or revoked shared recipe rows and temporary images via scheduled edge function.

CREATE EXTENSION IF NOT EXISTS "pg_cron";
CREATE EXTENSION IF NOT EXISTS "pg_net";

CREATE OR REPLACE FUNCTION public.get_expired_shared_recipe_links_for_cleanup(p_limit integer DEFAULT 100)
RETURNS TABLE (
  id uuid,
  image_path text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT srl.id, srl.image_path
  FROM public.shared_recipe_links srl
  WHERE srl.expires_at <= now()
     OR srl.revoked_at IS NOT NULL
  ORDER BY srl.expires_at ASC, srl.id ASC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500);
$$;

GRANT EXECUTE ON FUNCTION public.get_expired_shared_recipe_links_for_cleanup(integer) TO service_role;

DO $$
DECLARE
  v_job_name text := 'shared_recipe_links_cleanup';
  v_schedule text := '15 * * * *';
  v_command text;
  v_job_id integer;
  v_project_url text;
  v_anon_key text;
  v_cron_secret text;
BEGIN
  IF to_regclass('vault.decrypted_secrets') IS NULL THEN
    RAISE NOTICE 'Skipping shared recipe cleanup cron schedule; vault.decrypted_secrets is unavailable.';
    RETURN;
  END IF;

  SELECT decrypted_secret
  INTO v_project_url
  FROM vault.decrypted_secrets
  WHERE name = 'project_url'
  ORDER BY created_at DESC
  LIMIT 1;

  SELECT decrypted_secret
  INTO v_anon_key
  FROM vault.decrypted_secrets
  WHERE name IN ('anon_key', 'publishable_key')
  ORDER BY created_at DESC
  LIMIT 1;

  SELECT decrypted_secret
  INTO v_cron_secret
  FROM vault.decrypted_secrets
  WHERE name = 'recipe_share_cleanup_cron_secret'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_project_url IS NULL OR v_anon_key IS NULL OR v_cron_secret IS NULL THEN
    RAISE NOTICE 'Skipping shared recipe cleanup cron schedule; required Vault secrets are missing.';
    RETURN;
  END IF;

  v_command := format($cmd$
    select net.http_post(
      url := %L,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || %L,
        'x-cron-secret', %L
      ),
      body := jsonb_build_object('source', 'pg_cron'),
      timeout_milliseconds := 10000
    ) as request_id;
  $cmd$, v_project_url || '/functions/v1/cleanup-expired-recipe-shares', v_anon_key, v_cron_secret);

  IF to_regclass('cron.job') IS NOT NULL THEN
    IF EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'cron'
        AND table_name = 'job'
        AND column_name = 'jobname'
    ) THEN
      SELECT j.jobid INTO v_job_id
      FROM cron.job j
      WHERE j.jobname = v_job_name
      ORDER BY j.jobid DESC
      LIMIT 1;
    ELSE
      SELECT j.jobid INTO v_job_id
      FROM cron.job j
      WHERE j.command = v_command
      ORDER BY j.jobid DESC
      LIMIT 1;
    END IF;

    IF v_job_id IS NOT NULL THEN
      PERFORM cron.unschedule(v_job_id);
    END IF;
  END IF;

  IF to_regprocedure('cron.schedule(text,text,text)') IS NOT NULL THEN
    PERFORM cron.schedule(v_job_name, v_schedule, v_command);
  ELSE
    PERFORM cron.schedule(v_schedule, v_command);
  END IF;
END $$;
