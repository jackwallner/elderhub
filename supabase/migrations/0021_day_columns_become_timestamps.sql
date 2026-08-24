-- The pull has never worked on a device that did not author the data.
--
-- supabase-swift decodes every date with one strategy (`String.date`), and that
-- strategy only parses a full ISO8601 timestamp. PostgREST serialises a `date`
-- column as a bare "1939-07-13", which fails both of its attempts, and the
-- decode error takes down the whole page: one care recipient with a birthday
-- means a joining phone downloads no people at all, and `medications.start_date`
-- is `not null`, so it means no medications either.
--
-- Nobody saw it because the only phone with a record on it was the one that
-- typed the record in. The first person to accept an invitation got an empty
-- app, which is the whole product failing at the one moment it is being shown
-- to the family.
--
-- Fixed by changing the columns rather than the client, because the build in
-- the store cannot be changed and this reaches it today. The client already
-- sends these as full timestamps and Postgres was truncating them on the way
-- in, so nothing about the write path changes.
--
-- Existing values land at **noon** UTC, not midnight. Midnight UTC read back
-- through a US calendar is the evening before, which would move every birthday
-- and every start date back a day the moment this migration ran. Noon keeps the
-- calendar day intact anywhere within eleven hours of UTC.
--
-- `check_in_settings.last_escalated_on` is deliberately left a `date`. It is
-- server-side bookkeeping that the escalation query compares against a local
-- date, `CheckInSettingsDTO` does not carry it, and Codable ignores a key the
-- struct does not declare, so it was never part of this failure.

alter table public.care_recipients
    alter column birth_date type timestamptz
    using (birth_date + time '12:00') at time zone 'UTC';

alter table public.medications
    alter column start_date drop default;

alter table public.medications
    alter column start_date type timestamptz
    using (start_date + time '12:00') at time zone 'UTC';

alter table public.medications
    alter column start_date set default now();

alter table public.medications
    alter column end_date type timestamptz
    using (end_date + time '12:00') at time zone 'UTC';

alter table public.medications
    alter column last_filled_at type timestamptz
    using (last_filled_at + time '12:00') at time zone 'UTC';

notify pgrst, 'reload schema';
