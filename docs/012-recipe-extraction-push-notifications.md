# 012 — Recipe extraction push notifications

## Purpose

Persist native APNs/FCM device tokens and an idempotent delivery outbox for terminal recipe-extraction events. Notifications are attached only to the device that started a Pro background import. Expo Push Service is not used.

## Affected modules

- `supabase/migrations/20260722000000_create_extraction_push_notifications.sql`
- `supabase/migrations/20260722001000_remove_extraction_push_cron.sql`
- `supabase/functions/import-recipe/index.ts`
- `supabase/functions/import-recipe-image/index.ts`
- FastAPI sender contract: `../../fastapi/docs/012-recipe-extraction-push-notifications.md`
- Mobile registration contract: `../../nak-beli-apa-v2/docs/012-recipe-extraction-push-notifications.md`

## Data contract

`native_push_devices` stores an authenticated user's opaque APNs or FCM registration token, platform, APNs environment, language, and enabled state. Direct table access is service-role only. Authenticated clients use:

- `register_native_push_device(provider, environment, token, platform, language) -> uuid`
- `disable_native_push_device(device_id) -> boolean`
- `cancel_extraction_push_notification(imported_content_id) -> boolean`

`imported_content.notification_device_id` identifies the originating device. `notification_generation` increments when a failed import is retried so each attempt can have one terminal notification.

`extraction_push_deliveries` is the provider-delivery audit outbox. The unique `(imported_content_id, generation)` constraint makes terminal delivery creation idempotent. FastAPI immediately moves rows from `pending` to `processing`, then to `sent` or `failed` after bounded in-process attempts.

## API forwarding

Both import Edge Functions accept an optional `notification_device_id` and forward it to FastAPI.

## Delivery model

Delivery happens synchronously from FastAPI after the extraction terminal state is persisted. There is no `pg_cron`, `pg_net`, Vault, cron secret, or retry Edge Function dependency. Temporary provider failures receive bounded immediate retries; an exhausted delivery is recorded as `failed` and is not retried later.

## Migration and verification

1. Deploy both migrations. The follow-up migration safely removes an old extraction-push cron job and converts deferred rows if the original migration was previously applied.
2. Deploy both affected import Edge Functions.
3. Confirm authenticated RPC registration returns a device UUID while direct authenticated reads of token tables remain denied.
4. Complete, fail, and retry imports; confirm one outbox row per `(imported_content_id, notification_generation)`.
5. Confirm provider success ends as `sent` and exhausted provider errors end as `failed` without leaving pending rows.
