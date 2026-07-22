-- Remove deferred extraction-push retries in environments where the original
-- 20260722000000 migration was already applied.

DO $$
DECLARE
  v_job_id integer;
BEGIN
  IF to_regclass('cron.job') IS NULL THEN
    RETURN;
  END IF;

  FOR v_job_id IN
    SELECT j.jobid
    FROM cron.job j
    WHERE j.command LIKE '%/functions/v1/process-extraction-push-deliveries%'
  LOOP
    PERFORM cron.unschedule(v_job_id);
  END LOOP;
END $$;

DROP INDEX IF EXISTS public.extraction_push_deliveries_pending_idx;

ALTER TABLE public.extraction_push_deliveries
  DROP CONSTRAINT IF EXISTS extraction_push_deliveries_status_check;

UPDATE public.extraction_push_deliveries
SET
  status = 'failed',
  last_error_code = coalesce(last_error_code, 'DEFERRED_RETRY_REMOVED'),
  last_error_message = coalesce(
    last_error_message,
    'Deferred delivery retry was removed before this notification was delivered.'
  ),
  updated_at = now()
WHERE status IN ('pending', 'processing', 'permanent_failure');

ALTER TABLE public.extraction_push_deliveries
  ADD CONSTRAINT extraction_push_deliveries_status_check
    CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'permanent_failure'));

-- Keep the legacy next_attempt_at column, when present, for rolling-deploy
-- compatibility with an older FastAPI instance. New code does not read or
-- write it, and fresh databases created by the preceding migration omit it.
