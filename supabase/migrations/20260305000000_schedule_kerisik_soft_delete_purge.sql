-- Migration: 20260305000000_schedule_kerisik_soft_delete_purge
-- Description: Daily purge of kerisik.* soft-deleted rows older than 10 days.

-- pg_cron is used for scheduled jobs
CREATE EXTENSION IF NOT EXISTS "pg_cron";

-- Deletes rows where deleted_at is older than 10 days, for all kerisik.* tables
-- that have a deleted_at column.
CREATE OR REPLACE FUNCTION kerisik.purge_soft_deleted_rows()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  r record;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.schemata
    WHERE schema_name = 'kerisik'
  ) THEN
    RETURN;
  END IF;

  FOR r IN
    SELECT c.table_schema, c.table_name
    FROM information_schema.columns c
    WHERE c.table_schema = 'kerisik'
      AND c.column_name = 'deleted_at'
    ORDER BY c.table_name
  LOOP
    EXECUTE format(
      'DELETE FROM %I.%I WHERE deleted_at IS NOT NULL AND deleted_at < now() - interval %L',
      r.table_schema,
      r.table_name,
      '10 days'
    );
  END LOOP;
END;
$$;

ALTER FUNCTION kerisik.purge_soft_deleted_rows() OWNER TO postgres;

-- Schedule the purge daily (03:15 UTC).
DO $$
DECLARE
  v_job_name text := 'kerisik_purge_soft_deleted_rows';
  v_schedule text := '30 16 * * *';
  v_command text := 'select kerisik.purge_soft_deleted_rows();';
  v_job_id integer;
BEGIN
  -- Unschedule an existing job (by jobname when available, otherwise by command).
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

  -- Schedule with job name when supported, fallback to unnamed schedule otherwise.
  IF to_regprocedure('cron.schedule(text,text,text)') IS NOT NULL THEN
    PERFORM cron.schedule(v_job_name, v_schedule, v_command);
  ELSE
    PERFORM cron.schedule(v_schedule, v_command);
  END IF;
END $$;

